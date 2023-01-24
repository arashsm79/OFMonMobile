// ignore_for_file: deprecated_member_use, package_api_docs, public_member_api_docs
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:thingsboard_app/constants/app_constants.dart';
import 'package:thingsboard_app/core/sem/sem_db.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'dart:io' show Platform;

extension StringExtension on String {
  String truncateTo(int maxLength) =>
      (this.length <= maxLength) ? this : '${this.substring(0, maxLength)}...';
}

const NetworkSecurity STA_DEFAULT_SECURITY = NetworkSecurity.WPA;

class FlutterWifiIoT extends StatefulWidget {
  final Future<int> Function() connectHook;
  FlutterWifiIoT(this.connectHook);

  @override
  _FlutterWifiIoTState createState() => _FlutterWifiIoTState();
}

class Device {
  WifiNetwork? network;
  String? ssid;
  String? name;
  String? accessToken;
  String? tbId;
  String? profileTbId;
  int? version;
  int? lastChecked;
  Device(this.name, this.tbId, this.network, this.accessToken, this.version,
      this.profileTbId, this.lastChecked, this.ssid);
  @override
  String toString() {
    return "ssid: $ssid, last_checked: $lastChecked, accessToken: $accessToken, version: $version";
  }
}

class _FlutterWifiIoTState extends State<FlutterWifiIoT> {
  List<Device>? _deviceList;

  bool _isEnabled = false;
  bool _isConnected = false;
  Device? _connectedDevice;

  late Database _db;

  final TextStyle textStyle = TextStyle(color: Colors.white);

  @override
  initState() {
    () async {
      _db = await SemDb.getDb();
    }();
    WiFiForIoTPlugin.isEnabled().then((val) {
      _isEnabled = val;
    });

    WiFiForIoTPlugin.isConnected().then((val) {
      _isConnected = val;
    });

    super.initState();
  }

  Future<List<APClient>> getClientList(
      bool onlyReachables, int reachableTimeout) async {
    List<APClient> clients;

    try {
      clients = await WiFiForIoTPlugin.getClientList(
          onlyReachables, reachableTimeout);
    } on PlatformException {
      clients = <APClient>[];
    }

    return clients;
  }

  Future<List<Device>> loadWifiList() async {
    print("loading");
    List<Device> deviceList = [];
    List<WifiNetwork> accessPoints;
    try {
      accessPoints = await WiFiForIoTPlugin.loadWifiList();
      for (var ap in accessPoints) {
        if (ap.ssid != null &&
            ap.ssid!.startsWith(ThingsboardAppConstants.semSSID)) {
          print(ap.ssid);
          var dbDeviceList = (await _db
              .rawQuery("SELECT * FROM devices WHERE ssid = ?", [ap.ssid!]));
          if (dbDeviceList.length != 0) {
            var device = dbDeviceList[0];
            deviceList.add(Device(
                device['name'] as String?,
                device['tb_id'] as String?,
                ap,
                device['access_token'] as String?,
                device['version'] as int?,
                device['profile_tb_id'] as String?,
                device['last_checked'] as int?,
                ap.ssid!));
          } else {
            deviceList
                .add(Device(null, null, ap, null, null, null, null, ap.ssid!));
          }
        }
      }
    } on PlatformException {
      deviceList = <Device>[];
    }
    print(deviceList);

    return deviceList;
  }

  void showClientList() async {
    /// Refresh the list and show in console
    getClientList(false, 300).then((val) => val.forEach((oClient) {
          print("************************");
          print("Client :");
          print("ipAddr = '${oClient.ipAddr}'");
          print("hwAddr = '${oClient.hwAddr}'");
          print("device = '${oClient.device}'");
          print("isReachable = '${oClient.isReachable}'");
          print("************************");
        }));
  }

  bool _hasBeenCheckedRecently(Device device) {
    bool isNew = false;
    if (device.lastChecked != null) {
      var date = DateTime.fromMillisecondsSinceEpoch(device.lastChecked!);
      if (date.add(Duration(minutes: 10)).millisecondsSinceEpoch >
          DateTime.now().millisecondsSinceEpoch) {
        isNew = true;
      }
    }
    return isNew;
  }

  String _deviceLastChecked(Device device) {
    if (device.lastChecked != null) {
      var date = DateTime.fromMillisecondsSinceEpoch(device.lastChecked!);
      return date.toString();
    }
    return "";
  }

  Widget getWidgets() {
    WiFiForIoTPlugin.isConnected().then((val) {
      setState(() {
        _isConnected = val;
      });
    });

    // disable scanning for ios as not supported
    if (_isConnected || Platform.isIOS) {
      _deviceList = null;
    }

    List<Widget> widgets = [];

    if (_deviceList != null && _deviceList!.length > 0) {
      final List<ListTile> accessPointCards = <ListTile>[];

      _deviceList!.forEach((device) {
        final List<PopupMenuItem<PopupCommand>> popupMenuItems = [];

        popupMenuItems.add(
          PopupMenuItem<PopupCommand>(
            value: PopupCommand("Connect", device.ssid!),
            child: const Text('Connect'),
          ),
        );

        setState(() {
          var color = _hasBeenCheckedRecently(device)
              ? Colors.green
              : Theme.of(context).textTheme.labelLarge?.color;

          accessPointCards.add(
            ListTile(
              leading: Icon(
                Icons.devices_rounded,
                color: color,
              ),
              title: Row(children: [
                Text(
                  device.ssid!,
                  style: TextStyle(color: color),
                ),
              ]),
              subtitle: Text(
                (device.name ?? "").truncateTo(22) +
                    "\n" +
                    "" +
                    _deviceLastChecked(device),
                style: TextStyle(color: color),
                maxLines: 2,
              ),
              isThreeLine: true,
              trailing: PopupMenuButton<PopupCommand>(
                padding: EdgeInsets.zero,
                onSelected: (PopupCommand poCommand) {
                  switch (poCommand.command) {
                    case "Connect":
                      () async {
                        await WiFiForIoTPlugin.connect(device.ssid!,
                            password: ThingsboardAppConstants.deviceApPassword,
                            joinOnce: true,
                            security: STA_DEFAULT_SECURITY);
                        _connectedDevice = device;
                        var id = await widget.connectHook();
                        if (id >= 0) {
                          await _db.update(
                              "devices",
                              {
                                "ssid": device.ssid!,
                                "last_checked":
                                    DateTime.now().millisecondsSinceEpoch
                              },
                              where: "id = ?",
                              whereArgs: [id]);
                        }
                      }();
                      break;
                    case "Remove":
                      break;
                    default:
                      break;
                  }
                },
                itemBuilder: (BuildContext context) => popupMenuItems,
              ),
            ),
          );
        });
      });

      widgets = widgets + accessPointCards;
    } else {
      widgets = widgets +
          (Platform.isIOS
              ? getStatusWidgetsForiOS()
              : getStatusWidgetsForAndroid());
    }

    return Column(children: [
      Container(
          height: 220,
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.all(20),
            children: widgets,
          )),
      Align(
          child: SizedBox(
        width: 100,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
              primary: Theme.of(context).colorScheme.primary),
          child: Text("Scan", style: textStyle),
          onPressed: () async {
            _deviceList = await loadWifiList();
            setState(() {});
          },
        ),
      ))
    ]);
  }

  List<Widget> getStatusWidgetsForAndroid() {
    final List<Widget> statusWidgets = <Widget>[];

    WiFiForIoTPlugin.isEnabled().then((val) {
      setState(() {
        _isEnabled = val;
      });
    });

    if (_isEnabled) {
      WiFiForIoTPlugin.isConnected().then((val) {
        setState(() {
          _isConnected = val;
        });
      });

      if (_isConnected) {
        statusWidgets.addAll(<Widget>[
          Text("Connected", style: Theme.of(context).textTheme.titleMedium),
          FutureBuilder(
              future: WiFiForIoTPlugin.getSSID(),
              initialData: "Loading..",
              builder: (BuildContext context, AsyncSnapshot<String?> ssid) {
                return Text("SSID: ${ssid.data}",
                    style: Theme.of(context).textTheme.titleMedium);
              }),
          FutureBuilder(
              future: WiFiForIoTPlugin.getCurrentSignalStrength(),
              initialData: 0,
              builder: (BuildContext context, AsyncSnapshot<int?> signal) {
                return Text("Signal: ${signal.data}",
                    style: Theme.of(context).textTheme.titleMedium);
              }),
          Align(
              child: SizedBox(
            width: 120,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  primary: Theme.of(context).colorScheme.primary),
              child: Text("Disconnect", style: textStyle),
              onPressed: () async {
                await WiFiForIoTPlugin.disconnect();
                _connectedDevice = null;
              },
            ),
          )),
        ]);
      } else {
        statusWidgets.addAll(<Widget>[
          SizedBox(height: 10),
          Align(
              child: Text("Wifi Disconnected",
                  style: Theme.of(context).textTheme.titleLarge)),
        ]);
      }
    } else {
      statusWidgets.addAll(<Widget>[
        SizedBox(height: 10),
        Align(
            child: Text("Wifi Disabled",
                style: Theme.of(context).textTheme.titleLarge)),
      ]);
    }

    return statusWidgets;
  }

  List<Widget> getStatusWidgetsForiOS() {
    final List<Widget> htPrimaryWidgets = <Widget>[];

    WiFiForIoTPlugin.isEnabled().then((val) => setState(() {
          _isEnabled = val;
        }));

    if (_isEnabled) {
      htPrimaryWidgets.add(Text("Wifi Enabled"));
      WiFiForIoTPlugin.isConnected().then((val) => setState(() {
            _isConnected = val;
          }));

      if (_isConnected) {
        htPrimaryWidgets.addAll(<Widget>[
          Text("Connected"),
          FutureBuilder(
              future: WiFiForIoTPlugin.getSSID(),
              initialData: "Loading..",
              builder: (BuildContext context, AsyncSnapshot<String?> ssid) {
                return Text("SSID: ${ssid.data}");
              }),
        ]);
      }
    }
    return htPrimaryWidgets;
  }

  @override
  Widget build(BuildContext poContext) {
    return getWidgets();
  }
}

Future<void> forceWifiUsage(bool force) async {
  try {
    await WiFiForIoTPlugin.forceWifiUsage(force);
  } catch (e) {
    print("Failed to force wifi usage.");
  }
}

class PopupCommand {
  String command;
  String argument;

  PopupCommand(this.command, this.argument);
}
