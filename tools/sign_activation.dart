import 'dart:convert';
import 'dart:io';
import 'package:cryptography/cryptography.dart';

void main(List<String> args) async {
  if (args.length < 4) {
    _printUsage();
    exitCode = 64;
    return;
  }

  final companyCode = args[0].trim();
  final exp = args[1].trim(); // YYYY-MM-DD
  final privateKeyB64 = args[2].trim(); // raw 32-byte seed, base64url/base64
  final kid = args[3].trim();
  final plan = args.length >= 5 ? args[4].trim() : 'standard';
  final features = args.length >= 6
      ? args[5]
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList()
      : <String>[];

  if (companyCode.isEmpty || kid.isEmpty) {
    stderr.writeln('company_code and kid are required.');
    exitCode = 64;
    return;
  }
  final parsedExp = DateTime.tryParse(exp);
  if (parsedExp == null) {
    stderr.writeln('Invalid exp date. Use YYYY-MM-DD.');
    exitCode = 64;
    return;
  }

  final seed = _decodeB64(privateKeyB64);
  if (seed.length != 32) {
    stderr.writeln(
      'Ed25519 private key seed must be exactly 32 bytes (base64/base64url).',
    );
    exitCode = 64;
    return;
  }

  final payload = <String, dynamic>{
    'kid': kid,
    'company_code': companyCode,
    'plan': plan,
    'exp': '${parsedExp.year.toString().padLeft(4, '0')}-'
        '${parsedExp.month.toString().padLeft(2, '0')}-'
        '${parsedExp.day.toString().padLeft(2, '0')}',
    'features': features,
  };

  final payloadBytes = utf8.encode(jsonEncode(payload));
  final keyPair = await Ed25519().newKeyPairFromSeed(seed);
  final publicKey = await keyPair.extractPublicKey();
  final signature = await Ed25519().sign(payloadBytes, keyPair: keyPair);

  final activation = <String, dynamic>{
    'payload_b64': _encodeB64(payloadBytes),
    'sig_b64': _encodeB64(signature.bytes),
    'alg': 'Ed25519',
  };

  stdout.writeln('Activation key JSON:');
  stdout.writeln(jsonEncode(activation));
  stdout.writeln('');
  stdout.writeln('Public key (put in app for this kid):');
  stdout.writeln('kid=$kid');
  stdout.writeln('public_key_b64=${_encodeB64(publicKey.bytes)}');
}

void _printUsage() {
  stdout.writeln(
    'Usage:\n'
    'dart run tools/sign_activation.dart <company_code> <exp_yyyy-mm-dd> <private_seed_b64> <kid> [plan] [features_csv]\n'
    'Example:\n'
    'dart run tools/sign_activation.dart ACME-UK-001 2027-12-31 <seed_b64> k1 pro quality_scan,export_zip',
  );
}

List<int> _decodeB64(String value) {
  var v = value.trim().replaceAll('\n', '').replaceAll('\r', '');
  v = v.replaceAll('-', '+').replaceAll('_', '/');
  final rem = v.length % 4;
  if (rem > 0) v = '$v${'=' * (4 - rem)}';
  return base64.decode(v);
}

String _encodeB64(List<int> bytes) {
  return base64Url.encode(bytes).replaceAll('=', '');
}
