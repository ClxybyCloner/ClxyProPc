import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// What the sign-in engine asks for during authentication.
/// Mirrors Android's LoginPrompt (FxaLogin.kt).
enum LoginPrompt { password, totp, captcha, emailCode, unblockCode }

/// 100% native in-app Firefox Accounts (FxA) client for CLXY Cloud.
/// A faithful Dart port of Android's FxaLogin.kt (ClxyPro v1.5.14, tested),
/// replacing the old PC flow that delegated the whole login to the core's
/// /api/signin endpoint.
///
/// Implements, exactly like Android:
/// 1. Fastly anti-bot challenge solver (PoW, PAT, CAPTCHA, ClientMetrics),
///    applied reactively like Arman's fxaDo: when the API answers HTTP 406
///    (empty body), the challenge is solved and the SAME request retried,
///    up to 5 solves.
/// 2. PBKDF2 & HKDF password derivation (authPW)
/// 3. HAWK message authentication for session verification (email-2fa & TOTP)
/// 4. Account unblock challenge handling (errno 125)
///
/// Deliberate divergences from Android (architecture, not behavior):
/// - Android runs the engine on Dispatchers.IO and blocks on a queue; Dart
///   is async, so answers arrive through a Completer-free poll loop with
///   the same 5-minute deadline and 200 ms poll.
/// - Android's finishSuccess fetches the Remote Settings server list into
///   servers.json; on PC the server list comes from the core's /api/locations,
///   so that step is skipped (the status line is kept).
/// - The session token is handed to the Go core through POST
///   /api/signin/browser by the sign-in screen (the core verifies it,
///   exchanges the OAuth token and creates the account); on Android the
///   ffvpn binary reads session.txt itself.
class FxaLogin {
  FxaLogin(Directory workDir, {http.Client? client, FxaLogCallback? onLog})
      : _workDir = workDir,
        _client = client ?? http.Client(),
        _onLog = onLog;

  static const String fxaAuthServer = 'https://api.accounts.firefox.com/v1';
  static const String fxaApiHost = 'https://api.accounts.firefox.com';
  static const String fxaSiteUrl = 'https://accounts.firefox.com/';
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:128.0) Gecko/20100101 Firefox/128.0';
  static const String sessionFileName = 'session.txt';
  static const int tokenLength = 64;

  /// Arman's fxaDo bounds: max challenge solves per call, 90s budget.
  static const int maxChallengeAttempts = 5;
  static const Duration challengeBudget = Duration(seconds: 90);
  static const Duration answerTimeout = Duration(minutes: 5);
  static const Duration answerPoll = Duration(milliseconds: 200);

  final Directory _workDir;
  final http.Client _client;
  final FxaLogCallback? _onLog;

  bool _cancelled = false;
  final List<String> _answers = [];

  void answer(String value) {
    _answers.add(value.trim());
  }

  void cancel() {
    _cancelled = true;
  }

  void _log(String message) => _onLog?.call('sign-in', message);

  /// Executes the in-app CLXY Cloud sign-in.
  /// Returns null on success (with session.txt saved), or a human-readable
  /// error description.
  Future<String?> signIn({
    required String email,
    required String password,
    String unblockCode = '',
    required void Function(LoginPrompt) onPrompt,
    required void Function(String) onCaptcha,
    required void Function(String) onStatus,
  }) async {
    _cancelled = false;
    _answers.clear();

    final cleanEmail = email.trim();
    final cleanPassword = password.trim();
    final sessionFile = File('${_workDir.path}${Platform.pathSeparator}$sessionFileName');

    _log('Starting native FxA sign-in for $cleanEmail');

    // No up-front challenge solve: like Arman, the challenge is solved
    // only when the API actually answers HTTP 406, and the request is
    // then retried with the fresh cookie (see _fxaRequest).
    final cookies = <String, String>{};

    if (_cancelled) return 'Sign-in cancelled';

    onStatus('Deriving authentication credentials…');
    final String authPw;
    try {
      authPw = deriveAuthPW(cleanEmail, cleanPassword);
    } catch (e) {
      _log('Key derivation failed: $e');
      return 'Failed to derive credentials: $e';
    }

    onStatus('Connecting to CLXY Cloud…');
    final loginResult = await _loginWithRetries(
        cleanEmail, cleanPassword, authPw, unblockCode, cookies, onCaptcha, onStatus);
    if (_cancelled) return 'Sign-in cancelled';

    if (loginResult.isBlocked) {
      // Errno 125: Request blocked, unblock code required
      onStatus('CLXY Cloud security authorization required');
      await _sendUnblockCode(cleanEmail, cookies, onCaptcha, onStatus);
      onPrompt(LoginPrompt.unblockCode);
      final code = await _awaitAnswer();
      if (code == null) return 'Sign-in cancelled';
      if (code.isEmpty) return 'Authorization code is required';
      return signIn(
        email: cleanEmail,
        password: cleanPassword,
        unblockCode: code,
        onPrompt: onPrompt,
        onCaptcha: onCaptcha,
        onStatus: onStatus,
      );
    }

    if (loginResult.error != null) {
      _log('Login rejected: ${loginResult.error}');
      return loginResult.error;
    }

    final sessionToken = loginResult.sessionToken;
    if (sessionToken == null ||
        sessionToken.isEmpty ||
        sessionToken.length < tokenLength) {
      return 'CLXY Cloud did not return a valid session token';
    }

    if (loginResult.isVerified) {
      // Already verified (trusted device / no 2FA)
      return _finishSuccess(sessionFile, sessionToken, onStatus);
    }

    // Verification required: Email 2FA or TOTP
    switch (loginResult.verificationMethod) {
      case 'email-2fa':
        onStatus('Confirmation code sent to your email');
        _log('Email 2FA required for $cleanEmail');
        onPrompt(LoginPrompt.emailCode);
        final code = await _awaitAnswer();
        if (code == null) return 'Sign-in cancelled';
        if (code.isEmpty) return 'Verification code is required';

        onStatus('Verifying code…');
        final verifyErr = await _verifySession(
            sessionToken, code, false, cookies, onCaptcha, onStatus);
        if (verifyErr != null) {
          _log('Email verification failed: $verifyErr');
          return verifyErr;
        }
        return _finishSuccess(sessionFile, sessionToken, onStatus);
      case 'totp-2fa':
        onStatus('Authenticator code required');
        _log('TOTP 2FA required for $cleanEmail');
        onPrompt(LoginPrompt.totp);
        final code = await _awaitAnswer();
        if (code == null) return 'Sign-in cancelled';
        if (code.isEmpty) return 'Authenticator code is required';

        onStatus('Verifying authenticator code…');
        final verifyErr = await _verifySession(
            sessionToken, code, true, cookies, onCaptcha, onStatus);
        if (verifyErr != null) {
          _log('TOTP verification failed: $verifyErr');
          return verifyErr;
        }
        return _finishSuccess(sessionFile, sessionToken, onStatus);
      default:
        // If unknown method but session exists, try status check
        if (await _isSessionVerified(sessionToken, cookies, onCaptcha, onStatus)) {
          return _finishSuccess(sessionFile, sessionToken, onStatus);
        }
        return _finishSuccess(sessionFile, sessionToken, onStatus);
    }
  }

  String? _finishSuccess(
      File sessionFile, String sessionToken, void Function(String) onStatus) {
    try {
      sessionFile.parent.createSync(recursive: true);
      sessionFile.writeAsStringSync(sessionToken.trim());
      _log('Session token saved (${sessionToken.length} chars)');
    } catch (e) {
      return 'Failed to save session: $e';
    }

    onStatus('Updating server locations…');
    // Android fetches the Remote Settings server list into servers.json
    // here; on PC the server list comes from the core's /api/locations,
    // so there is nothing to fetch.
    onStatus('Connected to CLXY Cloud');
    return null;
  }

  /// Arman's fxaDo, ported: sends an FxA API request and, when the edge
  /// answers HTTP 406 (Fastly's bot check — an EMPTY body, no FxA error
  /// payload), solves the challenge and retries the SAME request, up to
  /// 5 solves within a 90s budget.
  Future<_FxaCall> _fxaRequest(
    String method,
    String url,
    String payload,
    String? hawkAuth,
    Map<String, String> cookies,
    void Function(String) onCaptcha,
    void Function(String) onStatus,
  ) async {
    final deadline = DateTime.now().add(challengeBudget);
    for (var solved = 0; solved <= maxChallengeAttempts; solved++) {
      if (_cancelled) return const _FxaCall(0, '', 'Sign-in cancelled');
      final call = await _sendOnce(method, url, payload, hawkAuth, cookies);
      if (call.error != null) return call;
      if (call.status != 406) return call;
      if (solved == maxChallengeAttempts) {
        _log('Fastly still answers HTTP 406 after $solved solved challenges');
        return _FxaCall(406, '',
            'HTTP 406: CLXY Cloud\'s security check refused this sign-in after $solved challenge solves');
      }
      if (DateTime.now().isAfter(deadline)) {
        return const _FxaCall(406, '',
            'HTTP 406: CLXY Cloud\'s security check timed out while solving its challenge');
      }
      _log('Account server answered HTTP 406 (Fastly bot check); solving challenge (attempt ${solved + 1})');
      onStatus('Solving security challenge…');
      if (!await _solveFastlyChallenge(cookies, onCaptcha, onStatus)) {
        if (_cancelled) return const _FxaCall(0, '', 'Sign-in cancelled');
        _log('Fastly challenge failed (attempt ${solved + 1})');
        return const _FxaCall(406, '',
            'HTTP 406: CLXY Cloud\'s security check refused this sign-in (challenge failed)');
      }
      _log('Fastly challenge solved; retrying request');
    }
    return const _FxaCall(406, '',
        'HTTP 406: CLXY Cloud\'s security check refused this sign-in');
  }

  /// One FxA HTTP request, with Arman's Firefox headers.
  Future<_FxaCall> _sendOnce(
    String method,
    String url,
    String payload,
    String? hawkAuth,
    Map<String, String> cookies,
  ) async {
    try {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': '*/*',
        // Arman: gzip as the sole encoding was associated with
        // HTTP 406 on the HTTP/1.1 path in live A/B tests.
        'Accept-Encoding': 'identity',
        'User-Agent': userAgent,
      };
      if (hawkAuth != null) headers['Authorization'] = hawkAuth;
      final cookieHdr = _formatCookies(cookies);
      if (cookieHdr.isNotEmpty) headers['Cookie'] = cookieHdr;

      final uri = Uri.parse(url);
      final http.Response res;
      if (method == 'GET') {
        res = await _client
            .get(uri, headers: headers)
            .timeout(const Duration(seconds: 30));
      } else {
        res = await _client
            .post(uri, headers: headers, body: payload)
            .timeout(const Duration(seconds: 30));
      }
      _extractCookies(res, cookies);
      return _FxaCall(res.statusCode, res.body, null);
    } catch (e) {
      return _FxaCall(0, '', _shortError(e));
    }
  }

  /// Login with Arman's fallbacks: errno 107 (the server rejects
  /// verificationMethod) retries without it; errno 120 (incorrect email
  /// case) retries once in the account's own letter case, as Firefox does.
  Future<_LoginAttemptResult> _loginWithRetries(
    String email,
    String password,
    String authPw,
    String unblockCode,
    Map<String, String> cookies,
    void Function(String) onCaptcha,
    void Function(String) onStatus,
  ) async {
    var result = await _attemptLogin(
        email, '', authPw, 'email-2fa', unblockCode, cookies, onCaptcha, onStatus);
    if (result.errno == 107) {
      _log('Server rejected verificationMethod (errno 107); retrying without it');
      result = await _attemptLogin(
          email, '', authPw, '', unblockCode, cookies, onCaptcha, onStatus);
    }
    if (result.errno == 120 &&
        result.correctedEmail.isNotEmpty &&
        result.correctedEmail != email) {
      _log('Retrying login in the account\'s own email case');
      final String fixedAuthPw;
      try {
        fixedAuthPw = deriveAuthPW(result.correctedEmail, password);
      } catch (e) {
        return _LoginAttemptResult(error: 'Failed to derive credentials: $e');
      }
      result = await _attemptLogin(result.correctedEmail, email, fixedAuthPw,
          'email-2fa', unblockCode, cookies, onCaptcha, onStatus);
    }
    return result;
  }

  Future<_LoginAttemptResult> _attemptLogin(
    String email,
    String originalEmail,
    String authPw,
    String verificationMethod,
    String unblockCode,
    Map<String, String> cookies,
    void Function(String) onCaptcha,
    void Function(String) onStatus,
  ) async {
    final target = '$fxaAuthServer/account/login';
    final body = <String, dynamic>{
      'email': email,
      'authPW': authPw,
    };
    if (originalEmail.isNotEmpty) body['originalLoginEmail'] = originalEmail;
    if (verificationMethod.isNotEmpty) {
      body['verificationMethod'] = verificationMethod;
    }
    if (unblockCode.trim().isNotEmpty) {
      body['unblockCode'] = unblockCode.trim().toUpperCase();
    }
    final payload = jsonEncode(body);

    final call =
        await _fxaRequest('POST', target, payload, null, cookies, onCaptcha, onStatus);
    if (call.error != null) return _LoginAttemptResult(error: call.error);
    if (call.status == 200) {
      final obj = _tryJson(call.body);
      if (obj == null) {
        return const _LoginAttemptResult(
            error: 'Invalid response from CLXY Cloud (HTTP 200)');
      }
      final token = obj['sessionToken'] as String? ?? '';
      // The login response carries only "verified" — there is no
      // "sessionVerified" field here (that lives on
      // /recovery_email/status). Requiring both made isVerified
      // always false, so even verified accounts were asked for a
      // code. Arman branches on Verified alone.
      final verified = obj['verified'] as bool? ?? false;
      final method = obj['verificationMethod'] as String? ?? 'email-2fa';
      return _LoginAttemptResult(
          sessionToken: token, isVerified: verified, verificationMethod: method);
    }
    final errObj = _tryJson(call.body);
    final errno = (errObj?['errno'] as num?)?.toInt() ?? 0;
    final msg = errObj?['message'] as String? ?? '';
    if (errno == 125) return const _LoginAttemptResult(isBlocked: true);
    // Never return an empty error: the UI shows the raw text as the
    // detail line, and errno lets it pick the right friendly message.
    final String detail;
    if (msg.isNotEmpty && errno != 0) {
      detail = '$msg (errno $errno, HTTP ${call.status})';
    } else if (msg.isNotEmpty) {
      detail = '$msg (HTTP ${call.status})';
    } else if (errno != 0) {
      detail = 'CLXY Cloud error (errno $errno, HTTP ${call.status})';
    } else {
      detail = 'CLXY Cloud error (HTTP ${call.status})';
    }
    final corrected = errObj?['email'] as String? ?? '';
    return _LoginAttemptResult(
        error: detail, errno: errno, correctedEmail: corrected);
  }

  Future<String?> _verifySession(
    String sessionToken,
    String code,
    bool isTotp,
    Map<String, String> cookies,
    void Function(String) onCaptcha,
    void Function(String) onStatus,
  ) async {
    final target = isTotp
        ? '$fxaAuthServer/session/verify/totp'
        : '$fxaAuthServer/session/verify_code';
    final payload = jsonEncode({'code': code.trim()});

    final HawkCredentials hawk;
    try {
      hawk = deriveHawkCredentials(sessionToken, 'sessionToken');
    } catch (e) {
      return e.toString();
    }
    final authHeader = hawkHeader('POST', target, hawk.id, hawk.key, payload);
    final call = await _fxaRequest(
        'POST', target, payload, authHeader, cookies, onCaptcha, onStatus);
    if (call.error != null) return call.error;
    if (call.status == 200) return null;
    final errObj = _tryJson(call.body);
    final msg = errObj?['message'] as String? ?? '';
    final errno = (errObj?['errno'] as num?)?.toInt() ?? 0;
    if (msg.isNotEmpty && errno != 0) {
      return '$msg (errno $errno, HTTP ${call.status})';
    } else if (msg.isNotEmpty) {
      return '$msg (HTTP ${call.status})';
    } else {
      return 'Code verification failed (HTTP ${call.status})';
    }
  }

  Future<bool> _isSessionVerified(
    String sessionToken,
    Map<String, String> cookies,
    void Function(String) onCaptcha,
    void Function(String) onStatus,
  ) async {
    final target = '$fxaAuthServer/recovery_email/status';
    try {
      final hawk = deriveHawkCredentials(sessionToken, 'sessionToken');
      final authHeader = hawkHeader('GET', target, hawk.id, hawk.key, '');
      final call = await _fxaRequest(
          'GET', target, '', authHeader, cookies, onCaptcha, onStatus);
      if (call.error == null && call.status == 200) {
        return _tryJson(call.body)?['sessionVerified'] as bool? ?? false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _sendUnblockCode(
    String email,
    Map<String, String> cookies,
    void Function(String) onCaptcha,
    void Function(String) onStatus,
  ) async {
    final target = '$fxaAuthServer/account/login/send_unblock_code';
    final payload = jsonEncode({'email': email});
    try {
      await _fxaRequest('POST', target, payload, null, cookies, onCaptcha, onStatus);
    } catch (_) {}
  }

  /// Solves the Fastly client challenge handshake and returns true if cleared.
  /// Tries the API host first (the host that actually rejected the request),
  /// then the site host — Arman's order. The API host usually serves no
  /// challenge page at all; the cookie the site host issues is scoped to
  /// firefox.com, so it clears the API host too.
  Future<bool> _solveFastlyChallenge(
    Map<String, String> cookies,
    void Function(String) onCaptcha,
    void Function(String) onStatus,
  ) async {
    for (final base in [fxaApiHost, fxaSiteUrl.replaceAll(RegExp(r'/+$'), '')]) {
      if (_cancelled) return false;
      if (await _solveChallengeOnHost(base, cookies, onCaptcha, onStatus)) {
        return true;
      }
    }
    return false;
  }

  /// Runs the whole challenge flow against one host. False = no challenge page here, or failed.
  Future<bool> _solveChallengeOnHost(
    String base,
    Map<String, String> cookies,
    void Function(String) onCaptcha,
    void Function(String) onStatus,
  ) async {
    try {
      final pageUrl = '$base/';
      final html = await _fetchText(pageUrl, cookies);
      if (html == null) return false;
      if (!_isChallengePage(html)) return false;

      final prefixMatch = RegExp(r'/_fs-ch-[A-Za-z0-9]+').firstMatch(html);
      if (prefixMatch == null) return false;
      final prefix = prefixMatch.group(0)!;

      final scriptUrl = '$base$prefix/script.js?reload=true';
      final scriptText = await _fetchText(scriptUrl, cookies);
      if (scriptText == null) return false;

      final init = parseChallengeInit(scriptText, prefix);
      if (init == null) return false;
      var challenges = init.challenges;
      var token = init.token;

      for (var round = 0; round < 8; round++) {
        if (_cancelled) return false;
        final answers = <Map<String, dynamic>>[];
        for (var i = 0; i < challenges.length; i++) {
          final ch = challenges[i] as Map<String, dynamic>;
          final ty = ch['ty'] as String? ?? '';
          final data = ch['data'] as Map<String, dynamic>? ?? {};

          switch (ty) {
            case 'pow':
              final powBase = data['base'] as String? ?? '';
              final targetHash = data['hash'] as String? ?? '';
              final ans = solvePow(powBase, targetHash);
              if (ans == null) return false;
              answers.add({
                'ty': 'pow',
                'base': powBase,
                'answer': ans,
                'hmac': data['hmac'] as String? ?? '',
                'expires': data['expires'] as String? ?? '',
              });
            case 'pat':
              // PAT challenge. A non-200 (401/400 when the
              // client cannot mint a PAT) posts back an empty
              // auth, which makes Fastly fall back to
              // solvable challenges — Arman's behavior.
              final patUrl =
                  '$base$prefix/pat?token=${Uri.encodeQueryComponent(token)}';
              var auth = '';
              try {
                final headers = <String, String>{
                  'User-Agent': userAgent,
                  'Content-Type': 'application/json',
                  'Accept': 'text/plain',
                  'Origin': base,
                };
                final cookieHdr = _formatCookies(cookies);
                if (cookieHdr.isNotEmpty) headers['Cookie'] = cookieHdr;
                final patRes = await _client
                    .post(Uri.parse(patUrl), headers: headers, body: '')
                    .timeout(const Duration(seconds: 10));
                _extractCookies(patRes, cookies);
                if (patRes.statusCode == 200) {
                  auth = _tryJson(patRes.body)?['auth'] as String? ?? '';
                }
              } catch (_) {}
              answers.add({'ty': 'pat', 'auth': auth});
            case 'clientmetrics':
              answers.add({
                'ty': 'clientmetrics',
                'webdriver': false,
                'bot_detection_result': {
                  'bot_detected': false,
                  'bot_kind': null,
                },
                'browser_metrics': {
                  'client_data': '{}',
                  'error_trace': null,
                },
                'detector_results': {},
                'v': 2,
              });
            case 'captcha':
              final imgB64 = data['image_b64'] as String? ?? '';
              // Never prompt with an unreadable image: the
              // user would sit at a dead-end input box.
              if (!imgB64.startsWith('data:image/')) {
                _log('Unrecognized CAPTCHA challenge data');
                return false;
              }
              onStatus('Security check: enter the characters below');
              onCaptcha(imgB64);
              final answer = await _awaitAnswer();
              if (answer == null) return false;
              answers.add({'ty': 'captcha', 'answer': answer.trim()});
            default:
              _log('Unsupported Fastly challenge type: $ty');
              return false;
          }
        }

        // Post-back
        final postBackUrl = '$base$prefix/fst-post-back';
        final pbPayload =
            jsonEncode({'token': token, 'data': answers});
        final headers = <String, String>{
          'User-Agent': userAgent,
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Origin': base,
        };
        final cookieHdr = _formatCookies(cookies);
        if (cookieHdr.isNotEmpty) headers['Cookie'] = cookieHdr;
        final pbRes = await _client
            .post(Uri.parse(postBackUrl), headers: headers, body: pbPayload)
            .timeout(const Duration(seconds: 20));
        _extractCookies(pbRes, cookies);
        if (pbRes.statusCode != 200) return false;

        final pbResp = _tryJson(pbRes.body);
        if (pbResp == null) return false;
        if (pbResp['status'] == 'success') {
          // Verify the challenge page clears before trusting the
          // cookies: a solved cookie can be rejected when the
          // exit IP rotated between solving and probing.
          final probe = await _fetchText(pageUrl, cookies);
          if (probe == null || _isChallengePage(probe)) {
            _log('Challenge cookie not accepted on probe; retrying on next host');
            return false;
          }
          _log('Fastly challenge successfully resolved!');
          return true;
        }
        final next = pbResp['ch'] as List<dynamic>?;
        if (next == null) break;
        challenges = next;
        token = pbResp['tok'] as String? ?? '';
        if (token.isEmpty) break;
      }
      return false;
    } catch (e) {
      _log('Fastly challenge solver exception: $e');
      return false;
    }
  }

  /// GETs a URL with the Firefox headers, collecting cookies. Null on any failure or non-200.
  Future<String?> _fetchText(String url, Map<String, String> cookies) async {
    try {
      final headers = <String, String>{
        'User-Agent': userAgent,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      };
      final cookieHdr = _formatCookies(cookies);
      if (cookieHdr.isNotEmpty) headers['Cookie'] = cookieHdr;
      final res = await _client
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 20));
      _extractCookies(res, cookies);
      if (res.statusCode != 200) return null;
      return res.body;
    } catch (_) {
      return null;
    }
  }

  /// Arman's challenge detection: the asset prefix AND the page marker.
  bool _isChallengePage(String html) =>
      html.contains('/_fs-ch-') && html.contains('Client Challenge');

  /// Parses the init([...], "token", "prefix") call from the challenge
  /// script with a real JSON decoder (Arman's approach): the old regex
  /// could not match a call spanning lines or nesting brackets, and never
  /// checked the prefix. Prefers the last valid call.
  static _ChallengeInit? parseChallengeInit(String scriptText, String prefix) {
    var searchFrom = 0;
    _ChallengeInit? found;
    while (true) {
      final idx = scriptText.indexOf('init', searchFrom);
      if (idx < 0) break;
      searchFrom = idx + 4;
      // Word boundary: skip "initialize", "reinit", ...
      if (idx > 0) {
        final prev = scriptText[idx - 1];
        if (_isWordChar(prev)) continue;
      }
      var p = idx + 4;
      while (p < scriptText.length && _isWhitespace(scriptText[p])) p++;
      if (p >= scriptText.length || scriptText[p] != '(') continue;
      final parsed = _parseInitCall(scriptText, p + 1, prefix);
      if (parsed == null) continue;
      found = parsed;
    }
    return found;
  }

  static _ChallengeInit? _parseInitCall(
      String s, int start, String prefix) {
    try {
      var p = start;
      final arr = _parseJsonValue(s, p);
      if (arr == null || arr.value is! List) return null;
      p = arr.end;
      p = _skipWs(s, p);
      if (p >= s.length || s[p] != ',') return null;
      p++;
      final tok = _parseJsonValue(s, p);
      if (tok == null || tok.value is! String) return null;
      p = tok.end;
      p = _skipWs(s, p);
      if (p >= s.length || s[p] != ',') return null;
      p++;
      final pre = _parseJsonValue(s, p);
      if (pre == null || pre.value is! String) return null;
      final token = tok.value as String;
      final scriptPrefix = pre.value as String;
      final list = arr.value as List<dynamic>;
      if (scriptPrefix != prefix || token.isEmpty || list.isEmpty) return null;
      return _ChallengeInit(list, token);
    } catch (_) {
      return null;
    }
  }

  /// Parses one JSON value (array, object or string) starting at [start]
  /// (after leading whitespace) and returns it with the index just past it.
  /// Returns null when the text there is not a parseable JSON value.
  static _JsonValue? _parseJsonValue(String s, int start) {
    var p = _skipWs(s, start);
    if (p >= s.length) return null;
    final c = s[p];
    if (c != '[' && c != '{' && c != '"') return null;
    if (c == '"') {
      p++;
      var closed = false;
      while (p < s.length) {
        final ch = s[p];
        if (ch == '\\') {
          p += 2;
          continue;
        }
        if (ch == '"') {
          closed = true;
          p++;
          break;
        }
        p++;
      }
      if (!closed) return null;
    } else {
      final open = c;
      final close = c == '[' ? ']' : '}';
      var depth = 0;
      var inString = false;
      while (p < s.length) {
        final ch = s[p];
        if (inString) {
          if (ch == '\\') {
            p += 2;
            continue;
          }
          if (ch == '"') inString = false;
          p++;
          continue;
        }
        if (ch == '"') {
          inString = true;
        } else if (ch == open) {
          depth++;
        } else if (ch == close) {
          depth--;
          if (depth == 0) {
            p++;
            break;
          }
        }
        p++;
      }
      if (depth != 0) return null;
    }
    final end = p;
    dynamic value;
    try {
      value = jsonDecode(s.substring(start, end));
    } catch (_) {
      return null;
    }
    return _JsonValue(value, end);
  }

  static int _skipWs(String s, int p) {
    while (p < s.length && _isWhitespace(s[p])) p++;
    return p;
  }

  static bool _isWhitespace(String c) =>
      c == ' ' || c == '\t' || c == '\n' || c == '\r';
  static bool _isWordChar(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 0x30 && code <= 0x39) ||
        (code >= 0x41 && code <= 0x5A) ||
        (code >= 0x61 && code <= 0x7A) ||
        c == '_' ||
        c == '\$';
  }

  static String? solvePow(String base, String targetHex) {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final baseBytes = ascii.encode(base);
    final cand = List<int>.filled(baseBytes.length + 2, 0);
    for (var i = 0; i < baseBytes.length; i++) {
      cand[i] = baseBytes[i];
    }
    for (var i = 0; i < alphabet.length; i++) {
      cand[baseBytes.length] = alphabet.codeUnitAt(i);
      for (var j = 0; j < alphabet.length; j++) {
        cand[baseBytes.length + 1] = alphabet.codeUnitAt(j);
        final hex = bytesToHex(sha256.convert(cand).bytes);
        if (hex.toLowerCase() == targetHex.toLowerCase()) {
          return '${alphabet[i]}${alphabet[j]}';
        }
      }
    }
    return null;
  }

  /// Collects Set-Cookie headers into [cookies]. The http package joins
  /// repeated Set-Cookie headers with ", ", so the combined value is
  /// split back apart, re-joining Expires date continuations (which
  /// contain a comma but no cookie name).
  static void _extractCookies(
      http.Response res, Map<String, String> cookies) {
    final combined = res.headers['set-cookie'];
    if (combined == null || combined.isEmpty) return;
    for (final cookie in _splitSetCookie(combined)) {
      final cookiePart = cookie.split(';')[0].trim();
      final eq = cookiePart.indexOf('=');
      if (eq > 0) {
        cookies[cookiePart.substring(0, eq).trim()] =
            cookiePart.substring(eq + 1).trim();
      }
    }
  }

  static List<String> _splitSetCookie(String header) {
    final parts = header.split(',');
    final out = <String>[];
    for (final part in parts) {
      final trimmed = part.trim();
      if (out.isNotEmpty &&
          !RegExp(r'^[^=;\s]+\s*=').hasMatch(trimmed)) {
        out[out.length - 1] = '${out.last},$part';
      } else {
        out.add(part);
      }
    }
    return out;
  }

  static String _formatCookies(Map<String, String> cookies) =>
      cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  Future<String?> _awaitAnswer() async {
    final deadline = DateTime.now().add(answerTimeout);
    while (!_cancelled && DateTime.now().isBefore(deadline)) {
      if (_answers.isNotEmpty) return _answers.removeAt(0);
      await Future.delayed(answerPoll);
    }
    return null;
  }

  static Map<String, dynamic>? _tryJson(String body) {
    try {
      final v = jsonDecode(body);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  static String _shortError(Object e) {
    final s = e.toString();
    // TimeoutException prints "TimeoutException after 0:00:30.000000:
    // Future not completed"; keep the useful part.
    return s.replaceFirst('TimeoutException after ', 'Timed out after ');
  }

  // -- Crypto (static, so unit tests can check them against the Go core) --

  /// PBKDF2-HMAC-SHA256 (1000 rounds, 32 bytes) then HKDF-Expand with
  /// info "identity.mozilla.com/picl/v1/authPW" — the FxA authPW.
  /// Matches Kotlin's deriveAuthPW and Go's deriveAuthPW (hawk.go):
  /// both use a zero HKDF salt (Go: one 0x00 byte, Kotlin: 32 zero
  /// bytes — identical after HMAC's zero-padding to the block size).
  static String deriveAuthPW(String email, String password) {
    final salt =
        utf8.encode('identity.mozilla.com/picl/v1/quickStretch:$email');
    final quickStretched =
        _pbkdf2Sha256(utf8.encode(password), salt, 1000, 32);

    final prk = _hmacSha256(List<int>.filled(32, 0), quickStretched);
    final info = utf8.encode('identity.mozilla.com/picl/v1/authPW');

    final mac = Hmac(sha256, prk);
    final out = mac.convert([...info, 1]).bytes;
    return bytesToHex(out);
  }

  /// HKDF with info "identity.mozilla.com/picl/v1/<context>":
  /// id = hex(T(1)), key = T(2). Matches Kotlin and Go.
  static HawkCredentials deriveHawkCredentials(
      String tokenHex, String contextStr) {
    final tokenBytes = hexToBytes(tokenHex);
    final prk = _hmacSha256(List<int>.filled(32, 0), tokenBytes);
    final info =
        utf8.encode('identity.mozilla.com/picl/v1/$contextStr');

    final mac = Hmac(sha256, prk);
    final t1 = mac.convert([...info, 1]).bytes;
    final t2 = mac.convert([...t1, ...info, 2]).bytes;

    return HawkCredentials(bytesToHex(t1), t2);
  }

  static String hawkHeader(String method, String rawUrl, String hawkId,
      List<int> hawkKey, [String payload = '']) {
    final url = Uri.parse(rawUrl);
    final nonce = _randomHex(6);
    final ts = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
    final port = url.hasPort
        ? url.port.toString()
        : (url.scheme == 'https' ? '443' : '80');
    var pathAndQuery = url.path;
    if (url.hasQuery) pathAndQuery += '?${url.query}';
    if (pathAndQuery.isEmpty) pathAndQuery = '/';

    var payloadHash = '';
    if (payload.isNotEmpty) {
      final bytes = <int>[];
      bytes.addAll(utf8.encode('hawk.1.payload\napplication/json\n'));
      bytes.addAll(utf8.encode(payload));
      bytes.addAll(utf8.encode('\n'));
      payloadHash = bytesToHex(sha256.convert(bytes).bytes);
    }

    final normalized = [
      'hawk.1.header',
      ts,
      nonce,
      method.toUpperCase(),
      pathAndQuery,
      url.host,
      port,
      payloadHash,
      '',
      '',
    ].join('\n');
    final mac = bytesToHex(_hmacSha256(hawkKey, utf8.encode(normalized)));

    var hdr = 'Hawk id="$hawkId", ts="$ts", nonce="$nonce", mac="$mac"';
    if (payloadHash.isNotEmpty) {
      hdr += ', hash="$payloadHash"';
    }
    return hdr;
  }

  /// PBKDF2-HMAC-SHA256. Only single-block outputs are used here
  /// (dkLen 32 = one SHA-256 block), but the loop is general.
  static List<int> _pbkdf2Sha256(
      List<int> password, List<int> salt, int iterations, int dkLen) {
    final out = <int>[];
    var blockIndex = 1;
    while (out.length < dkLen) {
      final blockSalt = [
        ...salt,
        (blockIndex >> 24) & 0xFF,
        (blockIndex >> 16) & 0xFF,
        (blockIndex >> 8) & 0xFF,
        blockIndex & 0xFF,
      ];
      var u = _hmacSha256(password, blockSalt);
      final t = List<int>.from(u);
      for (var i = 1; i < iterations; i++) {
        u = _hmacSha256(password, u);
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      out.addAll(t);
      blockIndex++;
    }
    return out.sublist(0, dkLen);
  }

  static List<int> _hmacSha256(List<int> key, List<int> data) =>
      Hmac(sha256, key).convert(data).bytes;

  static String bytesToHex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static List<int> hexToBytes(String hex) {
    final data = List<int>.filled(hex.length ~/ 2, 0);
    for (var i = 0; i < hex.length; i += 2) {
      data[i ~/ 2] =
          (int.parse(hex[i], radix: 16) << 4) + int.parse(hex[i + 1], radix: 16);
    }
    return data;
  }

  static String _randomHex(int lenBytes) {
    final bytes =
        List<int>.generate(lenBytes, (_) => Random.secure().nextInt(256));
    return bytesToHex(bytes);
  }
}

typedef FxaLogCallback = void Function(String level, String message);

class HawkCredentials {
  HawkCredentials(this.id, this.key);
  final String id;
  final List<int> key;
}

class _FxaCall {
  const _FxaCall(this.status, this.body, this.error);
  final int status;
  final String body;
  final String? error;
}

class _LoginAttemptResult {
  const _LoginAttemptResult({
    this.sessionToken,
    this.isVerified = false,
    this.verificationMethod = '',
    this.isBlocked = false,
    this.error,
    this.errno = 0,
    this.correctedEmail = '',
  });
  final String? sessionToken;
  final bool isVerified;
  final String verificationMethod;
  final bool isBlocked;
  final String? error;
  final int errno;

  /// The account's own email spelling, carried by errno 120.
  final String correctedEmail;
}

class _ChallengeInit {
  _ChallengeInit(this.challenges, this.token);
  final List<dynamic> challenges;
  final String token;
}

class _JsonValue {
  _JsonValue(this.value, this.end);
  final dynamic value;
  final int end;
}
