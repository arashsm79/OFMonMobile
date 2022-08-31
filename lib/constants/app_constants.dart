import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class ThingsboardAppConstants {
  static var storage = FlutterSecureStorage();
  static var thingsBoardApiEndpoint = 'http://108.122.255.24:9090';
  static var  deviceEndpoint = 'http://10.0.0.1';
  static var deviceApPassword = '12345678';
  static final thingsboardOAuth2CallbackUrlScheme = 'org.thingsboard.app.auth';

  /// Not for production (only for debugging)
  static final thingsboardOAuth2AppSecret = 'arashsecret';
}
