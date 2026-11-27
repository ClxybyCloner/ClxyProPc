import 'dart:convert';
import 'package:crypto/crypto.dart';

class QuantumSerial {
  // SHA-256 of the 12-character serials (uppercase, dashes stripped).
  // Rotated 2026-11-27: the old 5-character serials are burned — their
  // plaintext sat as comments next to the hashes in the public repo.
  // No serial plaintext lives anywhere in the source.
  static const Set<String> validHashes = {
    '2b205ae7577ae954f03890d0e7e4d4dfefdd3d45c93fcd68f08f78769f4c8b46',
    '360ac5242559a218171410effbe784e396f4fcff5436e2d2d8006ce0454b45b5',
    '80bcbb7c73d861f37ef825b360eeeb6c85fd6d44ba3351ef221b0e850af5540a',
    '61dcae65d329297dffc6c5de28e38c80b341ddf1dfb466966ff74407e4f84c54',
    '5f5cac4c5ad557746e8bd9e7571289867fe47c6a8ad6e55f89a6525ae22e0488',
    'd8afb795806113f63292067b5b005760563f8a1675bb5b1ff8023a2e12890134',
    'd608322903567e9ad2e4971aacdd2042a47b79908b94662cd1f1321e76cd1d08',
  };

  static bool isValid(String code) {
    final normalized = code
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (normalized.isEmpty) return false;
    final bytes = utf8.encode(normalized);
    final digest = sha256.convert(bytes);
    return validHashes.contains(digest.toString());
  }
}
