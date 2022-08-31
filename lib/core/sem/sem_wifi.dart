// ignore_for_file: deprecated_member_use, package_api_docs, public_member_api_docs
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:thingsboard_app/constants/app_constants.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'dart:io' show Platform;

const NetworkSecurity STA_DEFAULT_SECURITY = NetworkSecurity.WPA;

class FlutterWifiIoT extends StatefulWidget {
  @override
  _FlutterWifiIoTState createState() => _FlutterWifiIoTState();
}

class _FlutterWifiIoTState extends State<FlutterWifiIoT> {
  List<WifiNetwork?>? _accessPointList;
  Map<String, bool>? _registeredAccessPoints = Map();

  bool _isEnabled = false;
  bool _isConnected = false;

  final TextStyle textStyle = TextStyle(color: Colors.white);

  @override
  initState() {
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

  Future<List<WifiNetwork>> loadWifiList() async {
    List<WifiNetwork> accessPoints;
    try {
      accessPoints = await WiFiForIoTPlugin.loadWifiList();
    } on PlatformException {
      accessPoints = <WifiNetwork>[];
    }

    return accessPoints;
  }

  isRegisteredWifiNetwork(String ssid) async {
    bool isRegistered;

    try {
      isRegistered = await WiFiForIoTPlugin.isRegisteredWifiNetwork(ssid);
    } on PlatformException {
      isRegistered = false;
    }

    setState(() {
      _registeredAccessPoints![ssid] = isRegistered;
    });
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

  Widget getWidgets() {
    WiFiForIoTPlugin.isConnected().then((val) {
      setState(() {
        _isConnected = val;
      });
    });

    // disable scanning for ios as not supported
    if (_isConnected || Platform.isIOS) {
      _accessPointList = null;
    }

    List<Widget> widgets = [];

    if (_accessPointList != null && _accessPointList!.length > 0) {
      final List<ListTile> accessPointCards = <ListTile>[];
      HashSet<String> _uniqueAccessPoints = HashSet();

      _accessPointList!.forEach((accessPoint) {
        // Don't proccess duplicate access points
        if (_uniqueAccessPoints.contains(accessPoint!.ssid)) {
          return;
        } else {
          _uniqueAccessPoints.add(accessPoint.ssid!);
        }

        final List<PopupMenuItem<PopupCommand>> popupMenuItems = [];

        popupMenuItems.add(
          PopupMenuItem<PopupCommand>(
            value: PopupCommand("Connect", accessPoint.ssid!),
            child: const Text('Connect'),
          ),
        );

        setState(() {
          isRegisteredWifiNetwork(accessPoint.ssid!);
          if (_registeredAccessPoints!.containsKey(accessPoint.ssid) &&
              _registeredAccessPoints![accessPoint.ssid]!) {
            popupMenuItems.add(
              PopupMenuItem<PopupCommand>(
                value: PopupCommand("Remove", accessPoint.ssid!),
                child: const Text('Remove'),
              ),
            );
          }

          accessPointCards.add(
            ListTile(
              title: Text("" +
                  accessPoint.ssid! +
                  ((_registeredAccessPoints!.containsKey(accessPoint.ssid) &&
                          _registeredAccessPoints![accessPoint.ssid]!)
                      ? " *"
                      : "")),
              trailing: PopupMenuButton<PopupCommand>(
                padding: EdgeInsets.zero,
                onSelected: (PopupCommand poCommand) {
                  switch (poCommand.command) {
                    case "Connect":
                      WiFiForIoTPlugin.connect(accessPoint.ssid!,
                          password: ThingsboardAppConstants.deviceApPassword,
                          joinOnce: true,
                          security: STA_DEFAULT_SECURITY);
                      break;
                    case "Remove":
                      WiFiForIoTPlugin.removeWifiNetwork(poCommand.argument);
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
            _accessPointList = await loadWifiList();
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
              future: WiFiForIoTPlugin.getBSSID(),
              initialData: "Loading..",
              builder: (BuildContext context, AsyncSnapshot<String?> bssid) {
                return Text("BSSID: ${bssid.data}",
                    style: Theme.of(context).textTheme.titleMedium);
              }),
          FutureBuilder(
              future: WiFiForIoTPlugin.getCurrentSignalStrength(),
              initialData: 0,
              builder: (BuildContext context, AsyncSnapshot<int?> signal) {
                return Text("Signal: ${signal.data}",
                    style: Theme.of(context).textTheme.titleMedium);
              }),
          FutureBuilder(
              future: WiFiForIoTPlugin.getFrequency(),
              initialData: 0,
              builder: (BuildContext context, AsyncSnapshot<int?> freq) {
                return Text("Frequency : ${freq.data}",
                    style: Theme.of(context).textTheme.titleMedium);
              }),
          FutureBuilder(
              future: WiFiForIoTPlugin.getIP(),
              initialData: "Loading..",
              builder: (BuildContext context, AsyncSnapshot<String?> ip) {
                return Text("IP : ${ip.data}",
                    style: Theme.of(context).textTheme.titleMedium);
              }),
          Align(
              child: SizedBox(
            width: 120,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  primary: Theme.of(context).colorScheme.primary),
              child: Text("Disconnect", style: textStyle),
              onPressed: () {
                WiFiForIoTPlugin.disconnect();
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
  } catch (e, s) {
    print("Failed to force wifi usage.");
  }
}

class PopupCommand {
  String command;
  String argument;

  PopupCommand(this.command, this.argument);
}
