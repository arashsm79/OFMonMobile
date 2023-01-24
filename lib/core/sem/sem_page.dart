import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:http/http.dart' as http;
import 'package:http/http.dart';
import 'package:sqflite/sqflite.dart';
import 'package:thingsboard_app/constants/app_constants.dart';
import 'package:thingsboard_app/core/context/tb_context.dart';
import 'package:thingsboard_app/core/context/tb_context_widget.dart';
import 'package:thingsboard_app/core/entity/entities_base.dart';
import 'package:thingsboard_app/core/sem/sem_db.dart';
import 'package:thingsboard_app/core/sem/sem_utils.dart';
import 'package:thingsboard_app/core/sem/sem_wifi.dart';
import 'package:wifi_iot/wifi_iot.dart';

class CTReading {
  final int ctId;
  final double realPower;
  final double apparentPower;
  final double iRms;
  final double vRms;
  final double kwh;
  int timestamp;

  CTReading(this.ctId, this.realPower, this.apparentPower, this.iRms, this.vRms,
      this.kwh, this.timestamp);
  @override
  String toString() {
    return 'ctid: $ctId, realPower: $realPower: apparentPower: $apparentPower, iRms: $iRms, vRms: $vRms, kwh: $kwh, timestamp: $timestamp';
  }

  Map toJson() => {
        'ct_id': ctId,
        'real_power': realPower,
        'apparent_power': apparentPower,
        'i_rms': iRms,
        'v_rms': vRms,
        'kwh': kwh,
        'timestamp': timestamp
      };
}

class SemPage extends TbContextWidget {
  SemPage(TbContext tbContext) : super(tbContext);

  @override
  _SemPageState createState() => _SemPageState();
}

class _SemPageState extends TbContextState<SemPage>
    with AutomaticKeepAliveClientMixin<SemPage> {
  final _accessTokenFormKey = GlobalKey<FormBuilderState>();
  final _settingsFormKey = GlobalKey<FormBuilderState>();
  final _ctReadingSize = 30;
  late Database _db;
  List<ActionItem> _actionItems = [];
  bool _isPending = false;
  final PageLinkController _pageLinkController = PageLinkController();

  @override
  bool get wantKeepAlive {
    return true;
  }

  @override
  void initState() {
    () async {
      _db = await SemDb.getDb();
    }();
    super.initState();
    _getActionItems(tbContext);
  }

  Future<Map<String, dynamic>?> getTimeOnline() async {
    try {
      var res = await http.get(Uri.parse(
          'https://showcase.api.linx.twenty57.net/UnixTime/tounixtimestamp?datetime=now'));
      if (res.statusCode == 200) {
        return jsonDecode(res.body);
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  @override
  void dispose() {
    _pageLinkController.dispose();
    super.dispose();
  }

  Future<void> _clearLocalDb() async {
    await _db.rawQuery("DELETE FROM ota");
    await _db.rawQuery("DELETE FROM telemetry");
    await _db.rawQuery("DELETE FROM devices");
    log.info("Cleared DB");
  }

  Future<List<String>> _getLocalData() async {
    List<String> list = [];
    var telemetryList = await _db.rawQuery("SELECT * FROM telemetry");
    var deviceList = await _db.rawQuery("SELECT * FROM devices");
    var otaList = await _db.rawQuery("SELECT * FROM ota");

    list.add("###################### Devices ######################");
    list.add('\n');
    for (var v in deviceList) {
      list.add(v.toString());
      list.add('\n');
    }
    list.add("###################### OTA ######################");
    list.add('\n');
    for (var v in otaList) {
      list.add(v.toString());
      list.add('\n');
    }
    list.add("###################### Telemetry ######################");
    list.add('\n');
    for (var v in telemetryList) {
      list.add(v.toString());
      list.add('\n');
    }

    return list;
  }

  Future<int> _connectHook() async {
    log.info("Running connect hook.");
    // get device version
    var version = await _getVersion();

    var token = await _getToken();
    log.info("token: $token");
    if (token.isEmpty) {
      return -1;
    }
    var deviceProfileId = token.substring(20, 56);
    var id = await SemDb.getDeviceIdFromTokenOrAddNewDevice(_db, token);
    log.info("device profile id $deviceProfileId");

    var otaList = await _db.rawQuery(
        "SELECT * FROM ota WHERE profile_tb_id = ?", [deviceProfileId]);
    log.info(otaList);

    if (otaList.length == 0) {
      showInfoNotification(
          "No OTA package is available for this device. Device version: $version");
      await Future.delayed(Duration(seconds: 3));
      return id;
    }

    var otaVersion = otaList[0]['version'] as int;
    if (otaVersion <= version) {
      showInfoNotification(
          "No OTA package with newer version is available for this device. Device version: $version");
      await Future.delayed(Duration(seconds: 3));
      return id;
    }

    showInfoNotification(
        "There is a newer firmware available for this device. OTA Package $otaVersion > Device $version");

    return id;
  }

  Future<int> _getVersion() async {
    try {
      await forceWifiUsage(true).timeout(Duration(seconds: 30));
      var versionResponse = await http
          .get(
            Uri.parse(ThingsboardAppConstants.deviceEndpoint + '/version'),
          )
          .timeout(Duration(seconds: 30));
      log.info("version ${versionResponse.body}");
      return int.parse(versionResponse.body);
    } catch (e) {
      throw e;
    } finally {
      await forceWifiUsage(false);
    }
  }

  Future<void> _updateDevice() async {
    // get device version
    var version = await _getVersion();

    var deviceProfileId = (await _getToken()).substring(20, 56);
    log.info("device profile id $deviceProfileId");

    var otaList = await _db.rawQuery(
        "SELECT * FROM ota WHERE profile_tb_id = ?", [deviceProfileId]);
    log.info(otaList);

    if (otaList.length == 0) {
      showErrorNotification("No OTA package is available for this device.");
      await Future.delayed(Duration(seconds: 3));
      throw Error;
    }

    var otaVersion = otaList[0]['version'] as int;
    if (otaVersion <= version) {
      showErrorNotification(
          "No OTA package with newer version is available for this device.");
      await Future.delayed(Duration(seconds: 3));
      throw Error;
    }

    var otaPackagePath = otaList[0]['path'] as String;
    var fileData = (File(otaPackagePath).readAsBytesSync());

    log.info("ota length ${fileData.length}");

    try {
      await forceWifiUsage(true).timeout(Duration(seconds: 30));
      var otaResponse = await http
          .post(
            Uri.parse(ThingsboardAppConstants.deviceEndpoint + '/ota'),
            headers: {
              "Content-Type": "application/octet-stream",
              "X-FIRMWARE-VERSION": "$otaVersion",
            },
            body: fileData,
          )
          .timeout(Duration(seconds: 120));
    } catch (e) {
    } finally {
      await forceWifiUsage(false);
    }
  }

  Future<void> _sendToken(String token) async {
    try {
      log.info("seindg request");
      await forceWifiUsage(true).timeout(Duration(seconds: 30));
      var res = await http
          .post(Uri.parse(ThingsboardAppConstants.deviceEndpoint + '/token'),
              body: utf8.encode(token))
          .timeout(Duration(seconds: 2));
      log.info("got response");
      if (res.statusCode == 200) {
        _accessTokenFormKey.currentState?.reset();
        var accessToken = token.substring(0, 20);
        var profileTbId = token.substring(20, 56);
        var ssid = await WiFiForIoTPlugin.getSSID();
        var list =
            await _db.rawQuery("SELECT id FROM devices WHERE ssid = ?", [ssid]);
        if (list.length == 0) {
          await _db.insert(
            "devices",
            {
              "access_token": accessToken,
              "profile_tb_id": profileTbId,
              "ssid": ssid,
              "last_checked": DateTime.now().millisecondsSinceEpoch
            },
          );
        } else {
          await _db.update(
              "devices",
              {
                "access_token": accessToken,
                "profile_tb_id": profileTbId,
                "last_checked": DateTime.now().millisecondsSinceEpoch
              },
              where: 'ssid = ?',
              whereArgs: [ssid]);
        }
      }
    } catch (e) {
      throw e;
    } finally {
      await forceWifiUsage(false);
    }
  }

  Future<int> _sendTime() async {
    // send new time to device using ntp.
    var internetTime = await getTimeOnline();
    var unixTime = (internetTime == null)
        ? DateTime.now().millisecondsSinceEpoch
        : int.parse(internetTime['UnixTimeStamp']) * 1000;
    var timebuf = ByteData(8);
    timebuf.setUint64(0, unixTime, Endian.little);
    log.info("sending time: $unixTime");

    try {
      await forceWifiUsage(true).timeout(Duration(seconds: 30));
      await http
          .post(Uri.parse(ThingsboardAppConstants.deviceEndpoint + '/time'),
              body: timebuf.buffer.asUint8List())
          .timeout(Duration(seconds: 30));
    } catch (e) {
      throw e;
    } finally {
      await forceWifiUsage(false);
    }
    return unixTime;
  }

  Future<List<int>> _getPowerlossLog() async {
    Response response;
    try {
      await forceWifiUsage(true).timeout(Duration(seconds: 30));
      response = await http
          .get(
            Uri.parse(
                ThingsboardAppConstants.deviceEndpoint + '/powerloss_log'),
          )
          .timeout(Duration(seconds: 30));
    } catch (e) {
      throw e;
    } finally {
      await forceWifiUsage(false);
    }

    var bodyLength = response.bodyBytes.buffer.lengthInBytes;
    log.info("Got response with length $bodyLength");
    var bdata = response.bodyBytes.buffer.asByteData();
    // convert the binary data into a unix time stamp
    List<int> powerlossList = [];
    var offset = 0;
    for (int i = 0; i < bodyLength / _ctReadingSize; i++) {
      var timestamp = bdata.getUint64(offset + 0, Endian.little);
      offset += 8;

      // ignore false reports
      if (timestamp > 1661950000000) {
        powerlossList.add(timestamp);
      }
    }
    return powerlossList;
  }

  Future<String> _getToken({bool showOutput: false}) async {
    Response tokenResponse;
    try {
      await forceWifiUsage(true).timeout(Duration(seconds: 30));
      tokenResponse = await http
          .get(
            Uri.parse(ThingsboardAppConstants.deviceEndpoint + '/token'),
          )
          .timeout(Duration(seconds: 30));
      if (tokenResponse.statusCode != 200) {
        return "";
      }
    } catch (e) {
      throw e;
    } finally {
      await forceWifiUsage(false);
    }
    log.info(tokenResponse.body);
    if (showOutput) {
      await showDialog<bool>(
          context: widget.tbContext.currentState!.context,
          builder: (context) => AlertDialog(
                title: Text('Device Token'),
                content: SelectableText(tokenResponse.body),
                actions: [
                  TextButton(
                      onPressed: () => pop(true, context), child: Text('Ok'))
                ],
              ));
    }
    return tokenResponse.body;
  }

  Future<void> _initializeDevice(String token) async {
    await _sendToken(token);
    await _resetDevice();
    await _sendTime();
  }

  Future<void> _sendTokenDialog() async {
    showDialog<bool>(
      context: widget.tbContext.currentState!.context,
      builder: (context) => AlertDialog(
        title: Text('Send Token'),
        content: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  FormBuilder(
                      key: _accessTokenFormKey,
                      autovalidateMode: AutovalidateMode.disabled,
                      child: Padding(
                          padding: const EdgeInsets.only(left: 10, right: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              FormBuilderTextField(
                                name: 'access_token',
                                validator: FormBuilderValidators.compose([
                                  FormBuilderValidators.required(context,
                                      errorText: 'Token is required'),
                                ]),
                                decoration: InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                    labelText: 'Access Token'),
                              )
                            ],
                          ))),
                ]));
          },
        ),
        actions: [
          TextButton(
              onPressed: () => pop(true, context), child: Text('Cancel')),
          TextButton(
              onPressed: () async {
                if (!(_accessTokenFormKey.currentState?.saveAndValidate() ??
                    false)) {
                  return;
                }
                var formValue = _accessTokenFormKey.currentState!.value;
                String token = formValue['access_token'];
                _actionItemOnClickWrapper(() async {
                  await _sendToken(token);
                }, "Send Token");
                pop(true, context);
              },
              child: Text('Send')),
        ],
      ),
    );
  }

  Future<void> _initializeDeviceDialog() async {
    showDialog<bool>(
      context: widget.tbContext.currentState!.context,
      builder: (context) => AlertDialog(
        title: Text('Initialize Device'),
        content: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  FormBuilder(
                      key: _accessTokenFormKey,
                      autovalidateMode: AutovalidateMode.disabled,
                      child: Padding(
                          padding: const EdgeInsets.only(left: 10, right: 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              FormBuilderTextField(
                                name: 'access_token',
                                validator: FormBuilderValidators.compose([
                                  FormBuilderValidators.required(context,
                                      errorText: 'Token is required'),
                                ]),
                                decoration: InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                    labelText: 'Access Token'),
                              )
                            ],
                          ))),
                ]));
          },
        ),
        actions: [
          TextButton(
              onPressed: () => pop(true, context), child: Text('Cancel')),
          TextButton(
              onPressed: () async {
                if (!(_accessTokenFormKey.currentState?.saveAndValidate() ??
                    false)) {
                  return;
                }
                var ssid = await WiFiForIoTPlugin.getSSID();
                var deviceList = await _db.rawQuery(
                    'SELECT * FROM devices WHERE ssid = ? AND access_token IS NOT NULL',
                    [ssid]);
                if (deviceList.length != 0) {
                  showErrorNotification(
                      "This devices has already been initialized.");
                  return;
                }
                var formValue = _accessTokenFormKey.currentState!.value;
                String token = formValue['access_token'];
                _actionItemOnClickWrapper(() async {
                  await _initializeDevice(token);
                }, "Initialize Device");
                pop(true, context);
              },
              child: Text('Initialize')),
        ],
      ),
    );
  }

  Future<void> _collect() async {
    log.info("Collecting...");

    // First get the access token
    var token = await _getToken();
    log.info("Got token: $token");

    Response response;
    log.info("Getting telemetry.");
    try {
      await forceWifiUsage(true).timeout(Duration(seconds: 30));
      // get the telemtry data
      response = await http
          .get(
            Uri.parse(ThingsboardAppConstants.deviceEndpoint + '/telemetry'),
          )
          .timeout(Duration(seconds: 60));
    } catch (e) {
      throw e;
    } finally {
      await forceWifiUsage(false);
    }

    var recordId = await SemDb.getDeviceIdFromTokenOrAddNewDevice(_db, token);
    log.info(recordId);

    var bodyLength = response.bodyBytes.buffer.lengthInBytes;
    log.info("Got response with length $bodyLength");
    var bdata = response.bodyBytes.buffer.asByteData();

    // send current time to sensor
    log.info("Send time");
    var currentTime = await _sendTime();

    // get powerloss timestamps
    log.info("Get powerloss");
    var powerlossTimestamps = await _getPowerlossLog();
    log.info("powerloss ts $powerlossTimestamps");
    powerlossTimestamps.sort();
    powerlossTimestamps = powerlossTimestamps.toSet().toList();

    // convert the binary data into a struct and them one by one to the database.
    List<CTReading> responseList = [];
    var offset = 0;
    for (int i = 0; i < bodyLength / _ctReadingSize; i++) {
      var id = bdata.getUint16(offset + 0, Endian.little);
      var realPower = bdata.getFloat32(offset + 2, Endian.little);
      var apparentPower = bdata.getFloat32(offset + 6, Endian.little);
      var iRms = bdata.getFloat32(offset + 10, Endian.little);
      var vRms = bdata.getFloat32(offset + 14, Endian.little);
      var kwh = bdata.getFloat32(offset + 18, Endian.little);
      var timestamp = bdata.getUint64(offset + 22, Endian.little);
      var ctReading =
          CTReading(id, realPower, apparentPower, iRms, vRms, kwh, timestamp);
      offset += _ctReadingSize;
      responseList.add(ctReading);
    }

    // Calculate the difference between the timestamp of the latest reading and current time
    // We will distribute the error in between the powerlosses
    var powerlossTimestampsIndex = 0;
    if (powerlossTimestamps.isNotEmpty) {
      var addedDelta = 0;
      var errorDelta = currentTime - responseList.last.timestamp;
      // check only if errorDelta is bigger than an hour
      if (errorDelta > 3600000) {
        var intervalError = errorDelta ~/ powerlossTimestamps.length;
        log.info(
            "curtime: $currentTime, last response time: ${responseList.last.timestamp}");
        bool done = false;
        log.info("errorDelta: $errorDelta, intervalError: $intervalError");
        if (errorDelta > 0) {
          for (var i = 0; i < responseList.length; i++) {
            if (!done &&
                (responseList[i].timestamp >
                    powerlossTimestamps[powerlossTimestampsIndex])) {
              addedDelta += intervalError;
              log.info("added error interval");
              powerlossTimestampsIndex += 1;
              if (powerlossTimestampsIndex == powerlossTimestamps.length) {
                done = true;
              }
            }
            responseList[i].timestamp += addedDelta;
          }
        }
      }
    }

    log.info(responseList);
    for (var ctr in responseList) {
      await _db.insert('telemetry', {
        'ct_id': ctr.ctId,
        'real_power': ctr.realPower,
        'apparent_power': ctr.apparentPower,
        'power_factor': ctr.realPower / ctr.apparentPower,
        'i_rms': ctr.iRms,
        'v_rms': ctr.vRms,
        'kwh': ctr.kwh,
        'timestamp': ctr.timestamp,
        'device_id': recordId
      });
    }
    await _resetDevice();
  }

  Future<void> _resetDevice() async {
    await forceWifiUsage(true).timeout(Duration(seconds: 30));
    log.info("Resseting Device");
    try {
      var res = await http
          .get(
            Uri.parse(ThingsboardAppConstants.deviceEndpoint + '/reset'),
          )
          .timeout(Duration(seconds: 30));
      if (res.statusCode == 200) {
        log.info("Successfully reset device.");
      } else {
        log.info("Failed to reset device.");
      }
    } catch (e) {
      throw e;
    } finally {
      await forceWifiUsage(false);
    }
  }

  Future<void> _syncWithServer() async {
    // get a list of all devices
    var deviceList = await _db.rawQuery('SELECT * FROM devices');

    log.info(deviceList);
    for (var device in deviceList) {
      String accessToken = device['access_token']! as String;
      var telemetryList = await _db.rawQuery(
          'SELECT * FROM telemetry WHERE device_id = ?', [device['id']]);

      log.info(accessToken);

      // there are no telemetry data associated with this, device.
      // delete it
      if (telemetryList.length == 0) {
        await _db.rawQuery('DELETE FROM devices WHERE id = ?', [device['id']]);
        continue;
      }

      List<Map<String, dynamic>> jsonList = [];
      for (var telemetry in telemetryList) {
        jsonList.add({
          'ts': telemetry['timestamp'],
          'values': {
            'ct_id': telemetry['ct_id'],
            'real_power': telemetry['real_power'],
            'apparent_power': telemetry['apparent_power'],
            'i_rms': telemetry['i_rms'],
            'v_rms': telemetry['v_rms'],
            'kwh': telemetry['kwh'],
            'power_factor': telemetry['power_factor'],
          }
        });
      }

      // Send telemetry data to server
      log.info("Sending telemetry data to server.");
      var telemetryResponse = await http.post(
          Uri.parse(ThingsboardAppConstants.thingsBoardApiEndpoint +
              '/api/v1/' +
              accessToken +
              '/telemetry'),
          body: jsonEncode(jsonList));

      if (telemetryResponse.statusCode == 200) {
        log.info("Successfully synced telemetry data.");
      } else {
        throw Error;
      }
    }
    await _clearLocalDb();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(title: Text('Data Collection'), actions: <Widget>[
        PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case "settings":
                showDialog<bool>(
                  context: widget.tbContext.currentState!.context,
                  builder: (context) => AlertDialog(
                    title: Text('Settings'),
                    content: StatefulBuilder(
                      builder: (BuildContext context, StateSetter setState) {
                        return SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                              FormBuilder(
                                  key: _settingsFormKey,
                                  autovalidateMode: AutovalidateMode.disabled,
                                  child: Padding(
                                      padding: const EdgeInsets.only(
                                          left: 10, right: 10),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          SizedBox(height: 20),
                                          Text('Thingsboard Endpoint',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelLarge),
                                          SizedBox(height: 5),
                                          FormBuilderTextField(
                                            name: SemUtils.kThingsBoardEndpoint,
                                            initialValue:
                                                ThingsboardAppConstants
                                                    .thingsBoardApiEndpoint,
                                            validator:
                                                FormBuilderValidators.compose([
                                              FormBuilderValidators.url(context,
                                                  requireProtocol: true,
                                                  errorText:
                                                      'Enter a valid URL'),
                                            ]),
                                            decoration: InputDecoration(
                                                isDense: true,
                                                border: OutlineInputBorder(),
                                                labelText: 'URL'),
                                          ),
                                          SizedBox(height: 20),
                                          Text('Device Endpoint',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelLarge),
                                          SizedBox(height: 5),
                                          FormBuilderTextField(
                                            name: SemUtils.kDeviceEndpoint,
                                            initialValue:
                                                ThingsboardAppConstants
                                                    .deviceEndpoint,
                                            validator:
                                                FormBuilderValidators.compose([
                                              FormBuilderValidators.url(context,
                                                  requireProtocol: true,
                                                  errorText:
                                                      'Enter a valid URL'),
                                            ]),
                                            decoration: InputDecoration(
                                                isDense: true,
                                                border: OutlineInputBorder(),
                                                labelText: 'URL'),
                                          ),
                                          SizedBox(height: 20),
                                          Text('Device Access Point Password',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelLarge),
                                          SizedBox(height: 5),
                                          FormBuilderTextField(
                                            name: SemUtils.kDeviceApPassword,
                                            initialValue:
                                                ThingsboardAppConstants
                                                    .deviceApPassword,
                                            decoration: InputDecoration(
                                                isDense: true,
                                                border: OutlineInputBorder(),
                                                labelText: 'Password'),
                                          )
                                        ],
                                      ))),
                            ]));
                      },
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => pop(true, context),
                          child: Text('Cancel')),
                      TextButton(
                          onPressed: () async {
                            if (_settingsFormKey.currentState
                                    ?.saveAndValidate() ??
                                false) {
                              var settingsForm =
                                  _settingsFormKey.currentState?.value;

                              var tbEndpoint =
                                  settingsForm?[SemUtils.kThingsBoardEndpoint];
                              if (tbEndpoint != null) {
                                ThingsboardAppConstants.storage.write(
                                    key: SemUtils.kThingsBoardEndpoint,
                                    value: tbEndpoint);
                              }

                              var deviceEndpoint =
                                  settingsForm?[SemUtils.kDeviceEndpoint];
                              if (deviceEndpoint != null) {
                                ThingsboardAppConstants.storage.write(
                                    key: SemUtils.kDeviceEndpoint,
                                    value: deviceEndpoint);
                              }

                              var deviceApPassword =
                                  settingsForm?[SemUtils.kDeviceApPassword];
                              if (deviceApPassword != null) {
                                ThingsboardAppConstants.storage.write(
                                    key: SemUtils.kDeviceApPassword,
                                    value: deviceApPassword);
                              }

                              await SemUtils.setSettingValuesFromStorage();
                            }
                            pop(true, context);
                          },
                          child: Text('Save')),
                    ],
                  ),
                );
                break;
              case "local-data":
                _getLocalData();
                showDialog<bool>(
                  context: widget.tbContext.currentState!.context,
                  builder: (context) => AlertDialog(
                    title: Text('Local Data'),
                    content: StatefulBuilder(
                        builder: (BuildContext context, StateSetter setState) {
                      return SingleChildScrollView(
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                            FutureBuilder<List<String>>(
                                future: _getLocalData(),
                                builder: (
                                  BuildContext context,
                                  AsyncSnapshot<List<String>> snapshot,
                                ) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return Text("Loading");
                                  } else if (snapshot.connectionState ==
                                      ConnectionState.done) {
                                    if (snapshot.hasError) {
                                      return const Text('Error');
                                    } else if (snapshot.hasData) {
                                      return SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: Text(
                                              (snapshot.data!).toString()));
                                    }
                                  }
                                  return Text("Coudln't load data.");
                                })
                          ]));
                    }),
                    actions: [
                      TextButton(
                          onPressed: () async {
                            await _clearLocalDb();
                            pop(true, context);
                            showSuccessNotification("Cleared local storage.");
                          },
                          child: Text('Clear')),
                      TextButton(
                          onPressed: () => pop(true, context),
                          child: Text('Ok'))
                    ],
                  ),
                );
                break;
              default:
                break;
            }
          },
          itemBuilder: (BuildContext context) => <PopupMenuItem<String>>[
            PopupMenuItem<String>(
              value: "settings",
              child: const Text('Settings'),
            ),
            PopupMenuItem<String>(
              value: "local-data",
              child: const Text('Local Data'),
            ),
          ],
        ),
      ]),
      body: ListView(shrinkWrap: true, children: [
        FlutterWifiIoT(_connectHook),
        SizedBox(height: 8),
        _buildActionItems(context),
      ]),
    );
  }

  Widget _buildActionItems(BuildContext context) {
    List<Widget> items = _actionItems.map((actionItem) {
      return ElevatedButton(
          style: ElevatedButton.styleFrom(
            onPrimary: Theme.of(context).colorScheme.primary,
            primary: Theme.of(context).colorScheme.surface,
            shadowColor: Colors.transparent,
          ),
          child: Padding(
              padding: EdgeInsets.symmetric(vertical: 5, horizontal: 8),
              child: Row(mainAxisSize: MainAxisSize.max, children: [
                Icon(actionItem.icon,
                    color: Theme.of(context).textTheme.titleLarge?.color),
                SizedBox(width: 15),
                Text(actionItem.title,
                    style: TextStyle(
                        color: Theme.of(context).textTheme.titleLarge?.color,
                        fontStyle: FontStyle.normal,
                        fontWeight: FontWeight.w500,
                        fontSize: 20,
                        height: 20 / 14))
              ])),
          onPressed: () {
            actionItem.onClick();
          });
    }).toList();
    return Ink(
        color: Theme.of(context).colorScheme.surface,
        child: Column(children: items));
  }

  Future<void> _actionItemOnClickWrapper(
      Future<dynamic> Function() onClick, String msg,
      {bool showSuccess = true}) async {
    if (!_isPending) {
      try {
        showInfoNotification("Operation \"$msg\" started.");
        _isPending = true;
        await Future.delayed(Duration(seconds: 1));
        await onClick();
        if (showSuccess) {
          showSuccessNotification("Operation \"$msg\" finished.");
        }
      } catch (e) {
        showErrorNotification("Operation \"$msg\" failed.");
        log.info(e);
      } finally {
        _isPending = false;
      }
    }
  }

  _getActionItems(TbContext tbContext) {
    List<ActionItem> basicFunctions = [];
    List<ActionItem> advancedFunctions = [];

    advancedFunctions.addAll([
      ActionItem(
          title: 'Send Access Token',
          icon: Icons.lock_open,
          onClick: _sendTokenDialog),
      ActionItem(
          title: 'Get Access Token',
          icon: Icons.token_outlined,
          onClick: () {
            _actionItemOnClickWrapper(() async {
              await _getToken(showOutput: true);
            }, 'Get Access Token', showSuccess: false);
          }),
      ActionItem(
          title: 'Update Device Time',
          icon: Icons.more_time_rounded,
          onClick: () {
            _actionItemOnClickWrapper(_sendTime, 'Update Device Time');
          }),
      ActionItem(
          title: 'Reset Device',
          icon: Icons.reset_tv,
          onClick: () {
            _actionItemOnClickWrapper(_resetDevice, 'Reset Device');
          }),
    ]);

    basicFunctions.addAll([
      ActionItem(
        title: 'Initialize Device',
        icon: Icons.start,
        onClick: _initializeDeviceDialog,
      ),
      ActionItem(
          title: 'Collect Data from Device',
          icon: Icons.download_outlined,
          onClick: () {
            _actionItemOnClickWrapper(_collect, 'Collect from Device');
          }),
      ActionItem(
          title: 'Sync with Server',
          icon: Icons.upload_outlined,
          onClick: () {
            _actionItemOnClickWrapper(_syncWithServer, 'Sync with Server');
          }),
      ActionItem(
          title: 'Update Device Firmware',
          icon: Icons.update,
          onClick: () {
            _actionItemOnClickWrapper(_updateDevice, 'Update Device Firmware');
          }),
      ActionItem(
          title: 'More',
          icon: Icons.more_horiz_outlined,
          onClick: () {
            _actionItems.removeLast();
            _actionItems.addAll(advancedFunctions);
            setState(() {});
          }),
    ]);
    _actionItems = basicFunctions;
  }
}

class ActionItem {
  final String title;
  final IconData icon;
  final void Function() onClick;

  ActionItem({required this.title, required this.icon, required this.onClick});
}
