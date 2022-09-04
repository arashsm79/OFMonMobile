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
          ssid TEXT,
          profile_tb_id TEXT,
          version INTEGER
        );
      ''');
      await db.execute('''
        CREATE TABLE ota (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          tb_id TEXT UNIQUE,
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

}
