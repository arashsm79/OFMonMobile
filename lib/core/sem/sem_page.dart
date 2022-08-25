import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as Path;
import 'package:sqflite/sqflite.dart';
import 'package:thingsboard_app/core/context/tb_context.dart';
import 'package:thingsboard_app/core/context/tb_context_widget.dart';
import 'package:thingsboard_app/core/sem/sem_wifi.dart';

class CTReading {
  final int ctId;
  final double realPower;
  final double apparentPower;
  final double iRms;
  final double vRms;
  final double kwh;
  final int timestamp;

  CTReading(this.ctId, this.realPower, this.apparentPower, this.iRms, this.vRms,
      this.kwh, this.timestamp);
  @override
  String toString() {
    return 'id: $ctId, realPower: $realPower: apparentPower: $apparentPower, iRms: $iRms, vRms: $vRms, kwh: $kwh, timestamp: $timestamp';
  }
}

class SemPage extends TbPageWidget {
  SemPage(TbContext tbContext) : super(tbContext);

  @override
  _SemPageState createState() => _SemPageState();
}

class _SemPageState extends TbPageState<SemPage> {
  final _accessTokenFormKey = GlobalKey<FormBuilderState>();
  final _serverIp = "192.168.196.69:3000";
  final _ctReadingSize = 30;

  @override
  void initState() {
    super.initState();
  }

  Future<Database> initDb() async {
    // Get a location using getDatabasesPath
    var databasesPath = await getDatabasesPath();
    String path = Path.join(databasesPath, 'sem.db');
    log.info(path);
    // open the database
    Database database = await openDatabase(path, version: 1,
        onCreate: (Database db, int version) async {
      log.info("Creating sem database.");
      await db.execute('''
        CREATE TABLE devices (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          access_token TEXT NOT NULL
        );
      ''');
      await db.execute('''
        CREATE TABLE telemetry (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          ct_id INTEGER NOT NULL,
          real_power REAL,
          apparent_power REAL,
          i_rms REAL,
          v_rms REAL,
          power_factor NUMERIC,
          "timestamp" INTEGER,
          device_id INTEGER NOT NULL,
          CONSTRAINT telemetry_FK FOREIGN KEY (device_id) REFERENCES devices(id)
        );
      ''');
    });
    return database;
  }

  Future<Map<String, dynamic>?> getTime() async {
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
    super.dispose();
  }

  void _sendToken() async {
    if (_accessTokenFormKey.currentState?.saveAndValidate() ?? false) {
      var formValue = _accessTokenFormKey.currentState!.value;
      String token = formValue['access_token'];
      var res = await http
          .post(Uri.parse('http://' + _serverIp + '/token'),
              body: utf8.encode(token))
          .timeout(Duration(seconds: 2));
      if (res.statusCode == 200) {
        _accessTokenFormKey.currentState?.reset();
      }
    }
  }

  void _sendTime() async {
    // send new time to device using ntp.
    var internetTime = await getTime();
    var unixTime = (internetTime == null)
        ? DateTime.now().millisecondsSinceEpoch
        : int.parse(internetTime['UnixTimeStamp']) * 1000;
    var timebuf = ByteData(8);
    timebuf.setUint64(0, unixTime, Endian.little);
    log.info(unixTime);
    await http
        .post(Uri.parse('http://' + _serverIp + '/time'),
            body: timebuf.buffer.asUint8List())
        .timeout(Duration(seconds: 2));
  }

  void _collect() async {
    initDb().then((db) async {
      log.info("Collecting...");

      // First get the access token
      var tokenResponse = await http
          .get(
            Uri.parse('http://' + _serverIp + '/token'),
          )
          .timeout(Duration(seconds: 2));
      log.info(tokenResponse.body);

      // check whether a device with this access token eixsts
      var list = await db.rawQuery(
          'SELECT * FROM devices WHERE access_token = ?', [tokenResponse.body]);
      log.info(list);

      // if this is a new token, add it to device list otherwise return
      // the id of the existing device.
      int recordId = (list.length == 0)
          ? await db.insert('devices', {'access_token': tokenResponse.body})
          : list[0]['id'] as int;
      log.info(recordId);

      // get the telemtry data
      var response = await http
          .get(
            Uri.parse('http://' + _serverIp + '/telemetry'),
          )
          .timeout(Duration(seconds: 2));
      var bodyLength = response.bodyBytes.buffer.lengthInBytes;
      log.info("Got response with length $bodyLength");
      var bdata = response.bodyBytes.buffer.asByteData();

      // send current time to sensor
      _sendTime();

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

      log.info(responseList);
      for (var ctr in responseList) {
        await db.insert('telemetry', {
          'ct_id': ctr.ctId,
          'real_power': ctr.realPower,
          'apparent_power': ctr.apparentPower,
          'i_rms': ctr.iRms,
          'v_rms': ctr.vRms,
          'power_factor': ctr.realPower / ctr.apparentPower,
          'timestamp': ctr.timestamp,
          'device_id': recordId
        });
        log.info("inserted a record");
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Data Collection'), actions: <Widget>[
        PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case "disconnect":
                break;
              case "remove":
                break;
              default:
                break;
            }
          },
          itemBuilder: (BuildContext context) => <PopupMenuItem<String>>[
            PopupMenuItem<String>(
              value: "disconnect",
              child: const Text('Disconnect'),
            ),
            PopupMenuItem<String>(
              value: "remove",
              child: const Text('Remove'),
            ),
          ],
        ),
      ]),
      body: ListView(shrinkWrap: true, children: [
        FlutterWifiIoT(),
        SizedBox(height: 32),
        MaterialButton(
          color: Colors.blue,
          child: Text("Collect From Sensors"),
          onPressed: () {
            _collect();
          },
        ),
        MaterialButton(
          color: Colors.blue,
          child: Text("Sync With Server"),
          onPressed: () {
            log.info("pressed");
          },
        ),
        MaterialButton(
          color: Colors.blue,
          child: Text("Reset"),
          onPressed: () {
            log.info("pressed");
          },
        ),
        SizedBox(height: 32),
        FormBuilder(
            key: _accessTokenFormKey,
            autovalidateMode: AutovalidateMode.disabled,
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
                      border: OutlineInputBorder(), labelText: 'Access Token'),
                ),
              ],
            )),
        MaterialButton(
          color: Colors.blue,
          child: Text("Set Access Token"),
          onPressed: () {
            _sendToken();
          },
        ),
      ]),
    );
  }
}
