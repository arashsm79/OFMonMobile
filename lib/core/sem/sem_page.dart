import 'dart:typed_data';
import 'dart:ffi';

import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:http/http.dart' as http;
import 'package:thingsboard_app/core/context/tb_context.dart';
import 'package:thingsboard_app/core/context/tb_context_widget.dart';
import 'package:thingsboard_app/core/sem/sem_wifi.dart';

class CTReading {
  final int id;
  final double realPower;
  final double apparentPower;
  final double iRms;
  final double vRms;
  final double kwh;
  final int timestamp;

  CTReading(this.id, this.realPower, this.apparentPower, this.iRms, this.vRms,
      this.kwh, this.timestamp);
  @override
  String toString() {
      return 'id: $id, realPower: $realPower: apparentPower: $apparentPower, iRms: $iRms, vRms: $vRms, kwh: $kwh, timestamp: $timestamp';
    }
}

class SemPage extends TbPageWidget {
  SemPage(TbContext tbContext) : super(tbContext);

  @override
  _SemPageState createState() => _SemPageState();
}

class _SemPageState extends TbPageState<SemPage> {
  final _accessTokenFormKey = GlobalKey<FormBuilderState>();
  final _serverIp = "192.168.1.9:3000";
  final _ctReadingSize = 30;
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _collect() async {
    log.info("collecting...");
    var response = await http
        .get(
          Uri.parse('http://' + _serverIp + '/telemetry'),
        )
        .timeout(Duration(seconds: 2));
    var bodyLength = response.bodyBytes.buffer.lengthInBytes;
    var bdata = response.bodyBytes.buffer.asByteData();
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
      log.info(ctReading);
    }
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
      body: ListView(children: [
        FlutterWifiIoT(),
        SizedBox(height: 32),
        MaterialButton(
          color: Colors.blue,
          child: Text("Collect"),
          onPressed: () {
            _collect();
          },
        ),
        MaterialButton(
          color: Colors.blue,
          child: Text("Sync Time"),
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
            log.info("pressed");
          },
        ),
      ]),
    );
  }
}
