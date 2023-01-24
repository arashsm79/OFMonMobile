import 'package:path/path.dart' as Path;
import 'package:sqflite/sqflite.dart';

class SemDb {
  static Future<Database> getDb() async {
    // Get a location using getDatabasesPath
    var databasesPath = await getDatabasesPath();
    String path = Path.join(databasesPath, 'sem.db');
    // open the database
    Database database = await openDatabase(path, version: 1,
        onCreate: (Database db, int version) async {
      await db.execute('''
        CREATE TABLE devices (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          access_token TEXT NOT NULL,
          name TEXT,
          tb_id TEXT UNIQUE,
          ssid TEXT UNIQUE,
          profile_tb_id TEXT,
          version INTEGER,
          last_checked INTEGER
        );
      ''');
      await db.execute('''
        CREATE TABLE ota (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          tb_id TEXT,
          profile_tb_id TEXT UNIQUE,
          version INTEGER,
          path TEXT
        );
      ''');
      await db.execute('''
        CREATE TABLE telemetry (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          ct_id INTEGER NOT NULL,
          real_power REAL,
          apparent_power REAL,
          power_factor REAL,
          i_rms REAL,
          v_rms REAL,
          kwh REAL,
          "timestamp" INTEGER,
          device_id INTEGER NOT NULL,
          CONSTRAINT telemetry_FK FOREIGN KEY (device_id) REFERENCES devices(id)
        );
      ''');
    });
    return database;
  }

  static Future<int> getDeviceIdFromTokenOrAddNewDevice(Database db, String token) async {
    // check whether a device with this access token eixsts
    var accessToken = token.substring(0, 20);
    var profileTbId = token.substring(20, 56);
    var list = await db.rawQuery(
        'SELECT * FROM devices WHERE access_token = ?', [accessToken]);

    // if this is a new token, add it to device list otherwise return
    // the id of the existing device.
    int recordId = (list.length == 0)
        ? await db.insert('devices', {'access_token': accessToken, 'profile_tb_id': profileTbId})
        : list[0]['id'] as int;
    return recordId;
  }
}
