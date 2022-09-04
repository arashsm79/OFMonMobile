import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:http/http.dart' as http;
import 'package:http/http.dart';
import 'package:thingsboard_app/constants/app_constants.dart';
import 'package:thingsboard_app/core/context/tb_context.dart';
import 'package:thingsboard_app/core/context/tb_context_widget.dart';
import 'package:thingsboard_app/core/entity/entities_base.dart';
import 'package:thingsboard_app/core/sem/sem_db.dart';
import 'package:thingsboard_app/core/sem/sem_utils.dart';
import 'package:thingsboard_app/core/sem/sem_wifi.dart';

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
  bool _isPending = false;
  final PageLinkController _pageLinkController = PageLinkController();

  @override
  bool get wantKeepAlive {
    return true;
  }

  @override
  void initState() {
    super.initState();
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

  Future<void> _sendToken() async {
    if (_accessTokenFormKey.currentState?.saveAndValidate() ?? false) {
      var formValue = _accessTokenFormKey.currentState!.value;
      String token = formValue['access_token'];
      try {
        await forceWifiUsage(true);
        var res = await http
            .post(Uri.parse(ThingsboardAppConstants.deviceEndpoint + '/token'),
                body: utf8.encode(token))
            .timeout(Duration(seconds: 2));
        if (res.statusCode == 200) {
          _accessTokenFormKey.currentState?.reset();
        }
      } catch (e) {
        throw e;
      } finally {
        await forceWifiUsage(false);
      }
    } else {
      throw Error();
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
      await forceWifiUsage(true);
      await http
          .post(Uri.parse(ThingsboardAppConstants.deviceEndpoint + '/time'),
              body: timebuf.buffer.asUint8List())
          .timeout(Duration(seconds: 2));
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
      await forceWifiUsage(true);
      response = await http
          .get(
            Uri.parse(
                ThingsboardAppConstants.deviceEndpoint + '/powerloss_log'),
          )
          .timeout(Duration(seconds: 2));
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
      await forceWifiUsage(true);
      tokenResponse = await http
          .get(
            Uri.parse(ThingsboardAppConstants.deviceEndpoint + '/token'),
          )
          .timeout(Duration(seconds: 2));
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

  Future<void> _collect() async {
    var db = await SemDb.getDb();
    log.info("Collecting...");

    // First get the access token
    log.info("Getting token.");
    var token = await _getToken();

    Response response;
    log.info("Getting telemetry.");
    try {
      await forceWifiUsage(true);
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
    // check whether a device with this access token eixsts
    var list = await db
        .rawQuery('SELECT * FROM devices WHERE access_token = ?', [token]);
    log.info(list);

    // if this is a new token, add it to device list otherwise return
    // the id of the existing device.
    int recordId = (list.length == 0)
        ? await db.insert('devices', {'access_token': token})
        : list[0]['id'] as int;
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

    log.info(responseList);
    for (var ctr in responseList) {
      await db.insert('telemetry', {
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
      log.info("inserted a record");
    }
    await _resetDevice();
  }

  Future<void> _resetDevice() async {
    await forceWifiUsage(true);
    log.info("Resseting Device");
    try {
      var res = await http
          .get(
            Uri.parse(ThingsboardAppConstants.deviceEndpoint + '/reset'),
          )
          .timeout(Duration(seconds: 10));
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
    var db = await SemDb.getDb();
    // get a list of all devices
    var deviceList = await db.rawQuery('SELECT * FROM devices');

    log.info(deviceList);
    for (var device in deviceList) {
      String accessToken = device['access_token']! as String;
      var telemetryList = await db.rawQuery(
          'SELECT * FROM telemetry WHERE device_id = ?', [device['id']]);

      log.info(accessToken);
      log.info(telemetryList);

      // there are no telemetry data associated with this, device.
      // delete it
      if (telemetryList.length == 0) {
        await db.rawQuery('DELETE FROM devices WHERE id = ?', [device['id']]);
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

      print(jsonEncode(jsonList));
      // Send telemetry data to server
      await forceWifiUsage(true);
      var telemetryResponse = await http
          .post(
              Uri.parse(ThingsboardAppConstants.thingsBoardApiEndpoint +
                  '/api/v1/' +
                  accessToken +
                  '/telemetry'),
              body: jsonEncode(jsonList))
          .timeout(Duration(seconds: 2));
      await forceWifiUsage(false);

      if (telemetryResponse.statusCode == 200) {
        // log.info("Successfully synced telemetry data.");
        // await db.rawQuery('DELETE FROM telemetry WHERE device_id = ?', [device['id']]);
      }
    }
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
                      TextButton(
                          onPressed: () => pop(true, context),
                          child: Text('Cancel'))
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
          ],
        ),
      ]),
      body: ListView(shrinkWrap: true, children: [
        FlutterWifiIoT(),
        FormBuilder(
            key: _accessTokenFormKey,
            autovalidateMode: AutovalidateMode.disabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                    padding: const EdgeInsets.only(left: 10, right: 10),
                    child: FormBuilderTextField(
                      name: 'access_token',
                      validator: FormBuilderValidators.compose([
                        FormBuilderValidators.required(context,
                            errorText: 'Token is required'),
                      ]),
                      decoration: InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          labelText: 'Access Token'),
                    )),
              ],
            )),
        SizedBox(height: 8),
        _buildActionItems(context),
      ]),
    );
  }

  Widget _buildActionItems(BuildContext context) {
    List<Widget> items = _getActionItems(tbContext).map((actionItem) {
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

  List<ActionItem> _getActionItems(TbContext tbContext) {
    List<ActionItem> items = [];
    items.addAll([
      ActionItem(
          title: 'Send Access Token',
          icon: Icons.lock_open,
          onClick: () {
            _actionItemOnClickWrapper(_sendToken, 'Send Access Token');
          }),
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
          title: 'Collect from Device',
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
          title: 'Reset Device',
          icon: Icons.reset_tv,
          onClick: () {
            _actionItemOnClickWrapper(_resetDevice, 'Reset Device');
          }),
    ]);
    return items;
  }
}

class ActionItem {
  final String title;
  final IconData icon;
  final void Function() onClick;

  ActionItem({required this.title, required this.icon, required this.onClick});
}
