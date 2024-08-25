import 'dart:io';

import 'package:flutter/material.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:path/path.dart' as path;

import 'package:papermap_with_gps/common.dart';
import 'package:papermap_with_gps/map_calibration.dart';

class SettingsScreen extends StatefulWidget {
  MapAppSettings settings;

  SettingsScreen({super.key, required this.settings});

  @override
  SettingsScreenState createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> {
  late MapAppSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  Future<String?> _selectCSVFile(BuildContext context) async {
    String? result;
    Directory? rootdir;
    // String? exceptionStr;
    rootdir = await MapAppSettings.getRootDirectory();
    if (context.mounted) {
      result = await FilesystemPicker.openDialog(
        title: 'Pick a CSV file',
        context: context,
        rootDirectory: rootdir,
        fsType: FilesystemType.file,
        allowedExtensions: ['.csv'],
        fileTileSelectMode: FileTileSelectMode.wholeTile,
      );
    }
    return result;
  }

  void _clearCache() {
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Warning!"),
          content: const Text("Are you sure? This will remove all maps"),
          actions: <Widget>[
            TextButton(
              onPressed: () async {
                for (MapData map in _settings.mapFilesMetadata) {
                  File mapFile = File(map.fileName);
                  try {
                    mapFile.deleteSync();
                  } catch (e) {
                    //Ignore
                  }
                }
                Directory? rootdir = await MapAppSettings.getRootDirectory();
                String destDir =
                    path.join(rootdir.path, MapAppSettings.localMapDir);
                File csv = File(path.join(destDir, MapAppSettings.mapCsvFile));
                csv.deleteSync();
                _settings.mapFilesMetadata = List.empty(growable: true);
                Navigator.pop(ctx);
              },
              child: Container(
                color: Colors.red,
                padding: const EdgeInsets.all(14),
                child: const Text("OK"),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
              },
              child: Container(
                color: Colors.green,
                padding: const EdgeInsets.all(14),
                child: const Text("Cancel"),
              ),
            ),
          ],
        ),
      );
    }
  }

  void _listMaps() {
    if (context.mounted) {
      StringBuffer buffer = StringBuffer();
      int count = 0;
      for (MapData map in _settings.mapFilesMetadata) {
        File mapfile = File(map.fileName);
        buffer.writeln(path.basename(mapfile.path));
        count++;
      }
      buffer.writeln("Total maps stored: $count");
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Maps in Cache"),
          content: Expanded(
            child: SingleChildScrollView(
              child: Text(buffer.toString()),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                child: const Text("OK"),
              ),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Application Settings'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: ElevatedButton(
                onPressed: () async {
                  _settings.csvFileToImport = await _selectCSVFile(context);
                  if (context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
                child: const Text('Import Maps via CSV file'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: ElevatedButton(
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) =>
                          MapCalibrationScreen(settings: _settings),
                    ),
                  );
                },
                child: const Text('Calibrate maps'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Manual Entry'),
                  Switch(
                    value: _settings.isManualEnabled,
                    onChanged: (value) {
                      setState(() {
                        _settings.isManualEnabled = value;
                      });
                    },
                  )
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Show Position coords'),
                  Switch(
                    value: _settings.showPosition,
                    onChanged: (value) {
                      setState(() {
                        _settings.showPosition = value;
                      });
                    },
                  )
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Show Pan controls'),
                  Switch(
                    value: _settings.showPan,
                    onChanged: (value) {
                      setState(() {
                        _settings.showPan = value;
                      });
                    },
                  )
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Show Altitude'),
                  Switch(
                    value: _settings.showAltitude,
                    onChanged: (value) {
                      setState(() {
                        _settings.showAltitude = value;
                      });
                    },
                  )
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Direction Pointer'),
                  Switch(
                    value: _settings.isCompassPointerEnabled,
                    onChanged: (value) {
                      setState(() {
                        _settings.isCompassPointerEnabled = value;
                      });
                    },
                  )
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: ElevatedButton(
                onPressed: () {
                  _listMaps();
                },
                child: const Text('List Maps'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: ElevatedButton(
                onPressed: () {
                  _clearCache();
                },
                child: const Text('Clear Map Cache'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text('Done'),
              ),
            )
          ],
        ),
      ),
    );
  }
}
