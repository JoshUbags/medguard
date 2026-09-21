import 'dart:io';

Future<bool> defaultConnectivityProbe() async {
  try {
    final addresses = await InternetAddress.lookup(
      'example.com',
    ).timeout(const Duration(seconds: 3));
    return addresses.any((address) => address.rawAddress.isNotEmpty);
  } catch (_) {
    return false;
  }
}
