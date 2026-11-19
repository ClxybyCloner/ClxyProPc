import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../components/brand_header.dart';
import '../core/app_state.dart';
import '../core/fxa_login.dart';
import '../core/prefs.dart';
import '../theme/clxy_colors.dart';

/// 100% in-app native CLXY Cloud sign-in, ported from Android's
/// SignInActivity (ClxyPro v1.5.14, tested). The login runs in the app
/// itself (FxaLogin) — never through the core's /api/signin password flow.
/// The session token the engine returns is handed to the core through
/// POST /api/signin/browser, which verifies it, exchanges the OAuth token
/// and creates the account.
///
/// Why the old screen is gone: it delegated the login to the core and
/// decoded the core's CAPTCHA with a bare base64Decode() in build() —
/// but the core sends the CAPTCHA as a data URL ("data:image/..."),
/// so decoding threw during build and the whole window went gray the
/// moment a CAPTCHA appeared. Android's CaptchaImage strips the data-URL
/// prefix first and never throws in build; this screen does the same.
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
  final TextEditingController _unblockCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _busy = false;
  bool _showUnblock = false;
  String _status = '';
  String? _error;
  String _detail = '';
  LoginPrompt? _prompt;
  String _captcha = '';
  FxaLogin? _login;

  @override
  void initState() {
    super.initState();
    _emailCtrl.text = Prefs.sessionEmail;
  }

  @override
  void dispose() {
    _login?.cancel();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _codeCtrl.dispose();
    _unblockCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter the account email and password first.');
      return;
    }

    final driver = FxaLogin(
      Prefs.userDataDir,
      onLog: (level, msg) => widget.state.addLog(level, msg),
    );
    setState(() {
      _login = driver;
      _error = null;
      _detail = '';
      _codeCtrl.clear();
      _captcha = '';
      _prompt = null;
      _busy = true;
      _status = 'Signing in…';
    });

    final problem = await driver.signIn(
      email: email,
      password: password,
      unblockCode: _unblockCtrl.text.trim(),
      onPrompt: (p) {
        if (mounted) setState(() => _prompt = p);
      },
      // The prompt box only renders when `_prompt` is set, but the
      // CAPTCHA flow only fired onCaptcha — so the box (image + input)
      // never appeared and sign-in sat waiting with no way to type the
      // characters. Android fixed this the same way.
      onCaptcha: (img) {
        if (mounted) {
          setState(() {
            _captcha = img;
            _prompt = LoginPrompt.captcha;
          });
        }
      },
      onStatus: (line) {
        if (mounted) setState(() => _status = _cleanStatus(line));
      },
    );

    if (!mounted) return;
    if (problem == null) {
      final token = Prefs.sessionToken;
      if (token.length >= FxaLogin.tokenLength) {
        Prefs.sessionEmail = email;
        await _handToCore(email, token);
        return;
      }
      setState(() {
        _busy = false;
        _login = null;
        _prompt = null;
        _error = 'CLXY Cloud did not return a valid session token';
      });
      return;
    }

    setState(() {
      _busy = false;
      _login = null;
      _prompt = null;
      final failure = _describeFailure(problem);
      _error = failure.$1;
      _detail = failure.$2;
      if (problem.contains('errno 125') ||
          problem.toLowerCase().contains('authorization')) {
        _showUnblock = true;
      }
    });
  }

  String _cleanStatus(String line) {
    if (line.toLowerCase().contains('confirmation email')) {
      return 'Confirm the sign-in from your email, then wait here.';
    }
    return line
        .replaceAll(RegExp('Mozilla', caseSensitive: false), 'CLXY')
        .replaceAll(RegExp('Firefox', caseSensitive: false), 'CLXY');
  }

  /// Hands the FxA session token to the core, which verifies it, exchanges
  /// the OAuth token and creates the account. Polls the browser sign-in
  /// session until it finishes. Nothing is asked of the user here.
  Future<void> _handToCore(String email, String sessionToken) async {
    setState(() => _status = 'Adding the account…');
    final api = widget.state.coreProcess.api;
    if (api == null) {
      setState(() {
        _busy = false;
        _login = null;
        _error = widget.state.coreProcess.lastError ??
            'Core sidecar not connected. Please ensure core is running.';
      });
      return;
    }

    try {
      final url = api.endpoint.baseUri.replace(path: '/api/signin/browser');
      final res = await http
          .post(
            url,
            headers: {
              'X-Local-Token': api.endpoint.token,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'email': email, 'session_token': sessionToken}),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode != 200 && res.statusCode != 202) {
        final err = _tryJson(res.body);
        setState(() {
          _busy = false;
          _login = null;
          _error = err?['error']?.toString() ?? 'Account setup rejected';
        });
        return;
      }

      final data = _tryJson(res.body);
      final id = data?['id'] as String?;
      if (id == null || id.isEmpty) {
        setState(() {
          _busy = false;
          _login = null;
          _error = 'Account setup rejected';
        });
        return;
      }

      // Poll until done/failed. The session is already verified, so the
      // core normally finishes in seconds; bound the wait at 5 minutes.
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      while (mounted && DateTime.now().isBefore(deadline)) {
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        try {
          final poll = await http
              .get(
                api.endpoint.baseUri.replace(path: '/api/signin/$id'),
                headers: {'X-Local-Token': api.endpoint.token},
              )
              .timeout(const Duration(seconds: 5));
          if (poll.statusCode != 200) continue;
          final view = _tryJson(poll.body);
          if (view == null) continue;
          final step = view['step'] as String? ?? '';
          if (step == 'done') {
            Prefs.sessionToken =
                view['account_id']?.toString() ?? 'session_active';
            setState(() {
              _busy = false;
              _status = 'Signed in successfully!';
            });
            widget.onDone();
            return;
          }
          if (step == 'failed' || step == 'cancelled') {
            setState(() {
              _busy = false;
              _login = null;
              _error = (view['error'] as String?)?.isNotEmpty == true
                  ? view['error'] as String
                  : (view['message'] as String? ?? 'Sign-in failed');
            });
            return;
          }
        } catch (_) {
          // A failed poll is retried on the next tick.
        }
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _login = null;
          _error = 'Sign-in timed out. Check the connection and try again.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _login = null;
        _error = 'Sign-in error: $e';
      });
    }
  }

  void _submitCode() {
    _login?.answer(_codeCtrl.text);
    setState(() {
      _codeCtrl.clear();
      _captcha = '';
      _prompt = null;
      _error = null;
      _detail = '';
      _status = 'Signing in…';
    });
  }

  void _cancel() {
    _login?.cancel();
    Navigator.of(context).pop();
  }

  Map<String, dynamic>? _tryJson(String body) {
    try {
      final v = jsonDecode(body);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// Maps the engine's raw failure to Android's friendly message + detail.
  /// Strings are Android's sign_in_err_* verbatim.
  (String, String) _describeFailure(String? problem) {
    final raw = (problem ?? '').trim()
        .replaceAll(RegExp('Mozilla', caseSensitive: false), 'CLXY')
        .replaceAll(RegExp('Firefox', caseSensitive: false), 'CLXY');

    final String message;
    if (raw.toLowerCase().contains('captcha') ||
        raw.toLowerCase().contains('edge protection') ||
        raw.contains('HTTP 406')) {
      message =
          'CLXY Cloud\'s anti-bot check is blocking this sign-in and asks for a CAPTCHA the engine cannot answer. Try again in a few minutes, or from another network.';
    } else if (raw.contains('errno 103') ||
        raw.toLowerCase().contains('incorrect password')) {
      message = 'That password does not match this account.';
    } else if (raw.contains('errno 125')) {
      message =
          'CLXY Cloud blocked this sign-in and emailed an unblock code. Enter it below.';
    } else if (raw.contains('errno 201')) {
      message =
          'This account is not verified yet. Open CLXY Cloud\'s message, confirm the address, then sign in again.';
    } else if (raw.contains('errno 138')) {
      message =
          'CLXY Cloud has not confirmed this session yet. Approve the sign-in from your email, then try again.';
    } else if (raw.contains('errno 102')) {
      message = 'No CLXY Cloud Account uses this email.';
    } else if (raw.toLowerCase().contains('timed out')) {
      message = 'Sign-in timed out. Check the connection and try again.';
    } else if (raw.toLowerCase().contains('request to') ||
        raw.toLowerCase().contains('handshake') ||
        raw.contains('HTTP 5')) {
      message =
          'CLXY Cloud\'s servers could not be reached. Try again, or from another network.';
    } else {
      message = 'CLXY Cloud rejected this sign-in.';
    }
    final detail =
        (raw.isNotEmpty && raw != message) ? raw.take(180) : '';
    return (message, detail);
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
          onPressed: _cancel,
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
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

                if (_prompt != null) _buildPromptBox(),
                if (_prompt == null && _showUnblock) _buildUnblockForm(),
                if (_prompt == null && !_showUnblock) _buildCredentialsForm(),

                if (_status.isNotEmpty) ...[
                  const SizedBox(height: 16.0),
                  Text(
                    _status,
                    style: const TextStyle(
                        color: ClxyColors.cyanText, fontSize: 12.0),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12.0),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: ClxyColors.redDisconnectStart,
                      fontSize: 12.0,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (_detail.isNotEmpty) ...[
                  const SizedBox(height: 6.0),
                  Text(
                    _detail,
                    style: const TextStyle(
                        color: ClxyColors.textDim, fontSize: 10.5),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 8.0),
                TextButton(
                  onPressed: _cancel,
                  child: const Text(
                    'Close',
                    style: TextStyle(color: ClxyColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPromptBox() {
    final asking = _prompt!;
    final title = switch (asking) {
      LoginPrompt.totp => 'Two-Factor Authentication',
      LoginPrompt.emailCode => 'Email Verification Code',
      LoginPrompt.captcha => 'Security Verification',
      LoginPrompt.unblockCode => 'Account Unblock Code',
      LoginPrompt.password => 'Verification Required',
    };
    final hint = switch (asking) {
      LoginPrompt.totp => 'Enter the 6-digit authentication code from your app.',
      LoginPrompt.emailCode =>
        'Enter the 6-digit confirmation code sent to your email.',
      LoginPrompt.captcha => 'Type the characters shown in the picture below.',
      LoginPrompt.unblockCode =>
        'Enter the security unblock code sent to your email.',
      LoginPrompt.password => 'Enter the requested verification code.',
    };
    final numeric =
        asking == LoginPrompt.totp || asking == LoginPrompt.emailCode;

    return Container(
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(
            color: ClxyColors.cyanGlow.withOpacity(0.4), width: 1.0),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              color: ClxyColors.cyanText,
              fontWeight: FontWeight.w600,
              fontSize: 14.0,
            ),
          ),
          const SizedBox(height: 8.0),
          Text(
            hint,
            style: const TextStyle(
                color: ClxyColors.textMuted, fontSize: 11.5),
            textAlign: TextAlign.center,
          ),
          if (asking == LoginPrompt.captcha) ...[
            const SizedBox(height: 12.0),
            _CaptchaImage(dataUrl: _captcha),
          ],
          const SizedBox(height: 12.0),
          TextField(
            controller: _codeCtrl,
            keyboardType:
                numeric ? TextInputType.number : TextInputType.text,
            textAlign: TextAlign.center,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(
              color: ClxyColors.textPrimary,
              fontSize: 18.0,
              letterSpacing: 4.0,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              hintText: 'Enter code',
              hintStyle: const TextStyle(
                  color: ClxyColors.textDim, letterSpacing: 4.0),
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
              onPressed:
                  _codeCtrl.text.trim().isNotEmpty ? _submitCode : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: ClxyColors.blueDeep,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.0)),
              ),
              child: const Text(
                'Submit Code',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14.0,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnblockForm() {
    return Container(
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(14.0),
        border: Border.all(
            color: const Color(0xFFF59E0B).withOpacity(0.4), width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CLXY Cloud Authorization Code',
            style: TextStyle(
              color: Color(0xFFF59E0B),
              fontWeight: FontWeight.w600,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 8.0),
          const Text(
            'CLXY Cloud emailed an authorization code to verify your connection. Enter it below.',
            style: TextStyle(color: ClxyColors.textMuted, fontSize: 11.5),
          ),
          const SizedBox(height: 12.0),
          TextField(
            controller: _unblockCtrl,
            enabled: !_busy,
            style: const TextStyle(color: ClxyColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Authorization code',
              hintStyle: const TextStyle(color: ClxyColors.textDim),
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
          const SizedBox(height: 12.0),
          SizedBox(
            width: double.infinity,
            height: 48.0,
            child: ElevatedButton(
              onPressed: _busy ? null : _start,
              style: ElevatedButton.styleFrom(
                backgroundColor: ClxyColors.blueDeep,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.0)),
              ),
              child: const Text(
                'Confirm & Sign In',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 14.0,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Center(
            child: TextButton(
              onPressed: () => setState(() {
                _showUnblock = false;
                _unblockCtrl.clear();
              }),
              child: const Text(
                'Cancel Code',
                style: TextStyle(color: ClxyColors.textMuted, fontSize: 12.0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCredentialsForm() {
    return Column(
      children: [
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          enabled: !_busy,
          style: const TextStyle(color: ClxyColors.textPrimary),
          decoration: InputDecoration(
            labelText: 'Email Address',
            labelStyle: const TextStyle(color: ClxyColors.textMuted),
            prefixIcon: const Icon(Icons.mail_outline_rounded,
                color: ClxyColors.cyanGlow, size: 20.0),
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
          enabled: !_busy,
          style: const TextStyle(color: ClxyColors.textPrimary),
          decoration: InputDecoration(
            labelText: 'Password',
            labelStyle: const TextStyle(color: ClxyColors.textMuted),
            prefixIcon: const Icon(Icons.lock_outline_rounded,
                color: ClxyColors.cyanGlow, size: 20.0),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded,
                color: ClxyColors.textMuted,
                size: 20.0,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
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
            onPressed: _busy ? null : _start,
            style: ElevatedButton.styleFrom(
              backgroundColor: ClxyColors.blueDeep,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.0)),
            ),
            child: _busy
                ? const SizedBox(
                    width: 20.0,
                    height: 20.0,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Sign In',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 14.0,
                        fontWeight: FontWeight.bold),
                  ),
          ),
        ),
        TextButton(
          onPressed: () => setState(() => _showUnblock = true),
          child: const Text(
            'Have an authorization code?',
            style: TextStyle(color: ClxyColors.cyanText, fontSize: 12.0),
          ),
        ),
      ],
    );
  }
}

/// CAPTCHA image, mirroring Android's CaptchaImage: accepts a
/// "data:image/...;base64,..." URL or raw base64, and never throws in
/// build — a broken image shows a message instead of blanking the screen.
class _CaptchaImage extends StatelessWidget {
  const _CaptchaImage({required this.dataUrl});
  final String dataUrl;

  Uint8List? _decode() {
    final payload = dataUrl.contains('base64,')
        ? dataUrl.substring(dataUrl.indexOf('base64,') + 7)
        : dataUrl.trim();
    if (payload.isEmpty) return null;
    try {
      return base64Decode(payload);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _decode();
    if (bytes == null) {
      return const Text(
        'The CAPTCHA picture could not be shown.',
        style: TextStyle(
            color: ClxyColors.redDisconnectStart, fontSize: 11.0),
        textAlign: TextAlign.center,
      );
    }
    return Container(
      height: 110.0,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10.0),
      ),
      padding: const EdgeInsets.all(6.0),
      child: Image.memory(bytes, fit: BoxFit.contain),
    );
  }
}

extension on String {
  String take(int n) => length <= n ? this : substring(0, n);
}
