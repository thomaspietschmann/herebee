library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

class StyleRejected implements Exception {
  const StyleRejected(this.reason);
  final String reason;

  @override
  String toString() => 'StyleRejected: $reason';
}

const int _maxStyleBytes = 4 * 1024 * 1024;
const Duration _fetchTimeout = Duration(seconds: 15);

const Set<String> _urlKeys = {'url', 'urls', 'tiles', 'glyphs', 'sprite', 'data'};

final RegExp _schemeRe = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*:');
final RegExp _schemeSlashesRe = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.\-]*://');

class StyleGuard {
  StyleGuard(String origin) : _origin = _normalizeOrigin(origin);

  final Uri _origin;

  static Uri _normalizeOrigin(String origin) {
    final u = Uri.parse(origin);
    if ((u.scheme != 'https' && u.scheme != 'http') || u.host.isEmpty) {
      throw ArgumentError.value(origin, 'origin');
    }
    return u;
  }

  String get _prefix => '${_origin.scheme}://${_origin.authority}'.toLowerCase();

  bool isAllowedUrl(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return true;
    if (s.contains('\\') || s.contains(RegExp(r'[\s\x00-\x1f\x7f]'))) return false;
    if (s.toLowerCase().startsWith('pmtiles://')) {
      final inner = s.substring('pmtiles://'.length);
      return _schemeSlashesRe.hasMatch(inner) && _isSameOrigin(inner);
    }
    if (s.startsWith('//')) return _isSameOrigin('${_origin.scheme}:$s');
    if (_schemeRe.hasMatch(s)) return _isSameOrigin(s);
    return true;
  }

  bool _isSameOrigin(String absolute) {
    final lower = absolute.toLowerCase();
    if (!lower.startsWith(_prefix)) return false;
    final rest = lower.substring(_prefix.length);
    if (rest.isNotEmpty && !'/?#'.contains(rest[0])) return false;
    final Uri u;
    try {
      u = Uri.parse(absolute);
    } on FormatException {
      return false;
    }
    return u.scheme == _origin.scheme &&
        u.host == _origin.host.toLowerCase() &&
        u.port == _origin.port &&
        u.userInfo.isEmpty;
  }

  bool _looksLikeUrl(String s) {
    final t = s.trim();
    return t.startsWith('//') || _schemeSlashesRe.hasMatch(t);
  }

  void validate(Object? style) {
    if (style is! Map<String, dynamic>) throw const StyleRejected('not an object');
    _walk(style, null);
  }

  void _walk(Object? node, String? key) {
    if (node is String) {
      final urlField = key != null && _urlKeys.contains(key);
      if ((urlField || _looksLikeUrl(node)) && !isAllowedUrl(node)) {
        throw StyleRejected('foreign url at "$key": $node');
      }
    } else if (node is Map) {
      node.forEach((k, v) => _walk(v, k is String ? k : null));
    } else if (node is List) {
      for (final v in node) {
        _walk(v, key);
      }
    }
  }

  String validateJson(String body) {
    final Object? parsed;
    try {
      parsed = jsonDecode(body);
    } on FormatException {
      throw const StyleRejected('invalid json');
    }
    validate(parsed);
    return jsonEncode(parsed);
  }

  Future<String> fetch(String url, {HttpClient? client}) async {
    if (!_isSameOrigin(url)) throw const StyleRejected('style url off origin');
    final http = client ?? HttpClient();
    http.connectionTimeout = _fetchTimeout;
    try {
      final req = await http.getUrl(Uri.parse(url)).timeout(_fetchTimeout);
      req.followRedirects = false;
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final res = await req.close().timeout(_fetchTimeout);
      if (res.statusCode != HttpStatus.ok) {
        await res.drain<void>();
        throw StyleRejected('http ${res.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in res.timeout(_fetchTimeout)) {
        bytes.addAll(chunk);
        if (bytes.length > _maxStyleBytes) throw const StyleRejected('too large');
      }
      final String body;
      try {
        body = utf8.decode(bytes);
      } on FormatException {
        throw const StyleRejected('invalid utf-8');
      }
      return validateJson(body);
    } on StyleRejected {
      rethrow;
    } on Object catch (e) {
      throw StyleRejected('fetch failed: $e');
    } finally {
      if (client == null) http.close(force: true);
    }
  }
}
