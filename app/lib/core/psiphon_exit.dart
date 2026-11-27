// Psiphon exit behind Quantum (v1.5.31): the egress regions, the flag
// emoji for a country code, and the Guide texts (verbatim from Android
// v1.5.31, which took them from the Guide popup).

class PsiphonExit {
  /// Egress regions (ISO code to English name), the same set BPB-VPN
  /// offers. '' (not in the map) means Fastest (auto).
  static const Map<String, String> regions = {
    'AT': 'Austria',
    'AU': 'Australia',
    'BE': 'Belgium',
    'BG': 'Bulgaria',
    'CA': 'Canada',
    'CH': 'Switzerland',
    'CZ': 'Czechia',
    'DE': 'Germany',
    'DK': 'Denmark',
    'EE': 'Estonia',
    'ES': 'Spain',
    'FI': 'Finland',
    'FR': 'France',
    'GB': 'United Kingdom',
    'HR': 'Croatia',
    'HU': 'Hungary',
    'IE': 'Ireland',
    'IN': 'India',
    'IT': 'Italy',
    'JP': 'Japan',
    'LV': 'Latvia',
    'NL': 'Netherlands',
    'NO': 'Norway',
    'PL': 'Poland',
    'PT': 'Portugal',
    'RO': 'Romania',
    'RS': 'Serbia',
    'SE': 'Sweden',
    'SG': 'Singapore',
    'SK': 'Slovakia',
    'US': 'United States',
  };

  static const String autoLabel = 'Fastest (auto)';

  static String regionName(String code) {
    return regions[code.toUpperCase()] ?? code;
  }

  static const String guideTitle = 'How the exit country works';
  static const String guideTitleFa = 'کشور خروجی چطور کار می‌کنه؟';

  static const String guideBody =
      'With Quantum alone, the app picks the fastest route for you. Your traffic goes through Cloudflare\'s network and comes out with an IP that shows as Tehran, Iran — so websites see you as being in Tehran, and you can\'t pick another country.\n\nTurn on Change Iran Exit and your traffic takes one extra hop through Psiphon, then comes out onto the internet from the country you pick above. Websites and apps then see you as being in that country. Choose Fastest (auto) and Psiphon picks the quickest country for you.';

  static const String guideBodyFa =
      'با کوانتومِ تنها، برنامه خودش سریع‌ترین مسیر رو برات انتخاب می‌کنه. ترافیکت از شبکه‌ی کلادفلر رد می‌شه و با یه آی‌پی تهران میای بیرون — یعنی سایت‌ها تو رو اهل تهران (ایران) می‌بینن و خودت نمی‌تونی کشور دیگه‌ای انتخاب کنی.\n\nاگه «تغییر خروجی ایران» رو روشن کنی، ترافیکت یه قدم اضافه از سایفون رد می‌شه و از کشوری که بالا انتخاب کردی وارد اینترنت می‌شه. سایت‌ها و برنامه‌ها تو رو اهل همون کشور می‌بینن. اگه «سریع‌ترین» رو بزنی، سایفون خودش سریع‌ترین کشور رو برات انتخاب می‌کنه.';

  /// The core's Psiphon failure, in the app's words (Android's
  /// FailureText.PSIPHON_FAILED): any raw error starting with
  /// 'psiphon:' means the exit did not come up while Quantum itself
  /// connected.
  static const String failedMessage =
      'Psiphon exit did not come up (Quantum itself connected) — try another region or turn the exit off';

  static bool isPsiphonError(String message) {
    return message.toLowerCase().startsWith('psiphon:');
  }
}
