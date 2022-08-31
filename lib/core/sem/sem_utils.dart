import 'package:thingsboard_app/constants/app_constants.dart';

class SemUtils {
  static final String kThingsBoardEndpoint = 'thingsboard_endpoint';
  static final String kDeviceEndpoint = 'device_endpoint';
  static final String kDeviceApPassword = 'device_ap_endpoint';
  static Future<void> setSettingValuesFromStorage() async {
    var tbEndpoint =
        await ThingsboardAppConstants.storage.read(key: kThingsBoardEndpoint);
    if (tbEndpoint != null) {
      ThingsboardAppConstants.thingsBoardApiEndpoint = tbEndpoint;
    }

    var deviceEndpoint =
        await ThingsboardAppConstants.storage.read(key: kDeviceEndpoint);
    if (deviceEndpoint != null) {
      ThingsboardAppConstants.deviceEndpoint = deviceEndpoint;
    }

    var deviceApPassword =
        await ThingsboardAppConstants.storage.read(key: kDeviceApPassword);
    if (deviceApPassword != null) {
      ThingsboardAppConstants.deviceApPassword = deviceApPassword;
    }
  }
}
