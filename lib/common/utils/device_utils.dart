import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract final class DeviceUtils {
  static const _channel = MethodChannel('com.adguard.trusttunnel/device');

  static Future<bool> isTelevision() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;

    try {
      return await _channel.invokeMethod<bool>('isTelevision') ?? false;
    } on MissingPluginException {
      return false;
    }
  }
}
