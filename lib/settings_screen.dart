import 'dart:io';

import 'package:flutter/material.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

// Import all necessary files from the original screen
import 'package:papermap_with_gps/common.dart';
import 'package:papermap_with_gps/map_calibration.dart';
import 'package:papermap_with_gps/show_map_screen.dart';

class SettingsScreen extends StatefulWidget {
  MapAppSettings settings;

  SettingsScreen({super.key, required this.settings});

  @override
  SettingsScreenState createState() => SettingsScreenState(settings: settings);
}

class SettingsScreenState extends State<SettingsScreen> {
  SettingsScreenState({required MapAppSettings settings})
    : _settings = settings;

  MapAppSettings _settings;

  @override
  void initState() {
    super.initState();
  }

  // --- Helper Methods (Copied from original) ---

  Future<String?> _selectCSVFile(BuildContext context) async {
    String? result;
    Directory? rootdir;
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
        builder:
            (ctx) => AlertDialog(
              title: const Text("Warning!"),
              content: const Text(
                "Are you sure? This will remove all maps and local data.",
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () async {
                    for (MapData map in _settings.mapFilesMetadata) {
                      File mapFile = File(map.fileName);
                      try {
                        mapFile.deleteSync();
                      } catch (e) {
                        // Ignore
                      }
                    }
                    Directory? rootdir = await getExternalStorageDirectory();
                    rootdir ??= await getApplicationDocumentsDirectory();
                    String destDir = path.join(
                      rootdir.path,
                      MapAppSettings.localMapDir,
                    );
                    File csv = File(
                      path.join(destDir, MapAppSettings.mapCsvFile),
                    );
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

  void _loadGPX({bool add = false}) async {
    final filePath = await FilesystemPicker.openDialog(
      title: 'Pick a GPX file',
      context: context,
      rootDirectory: Directory(_settings.mapDir!),
      fsType: FilesystemType.file,
      allowedExtensions: ['.gpx', '.xml'],
      fileTileSelectMode: FileTileSelectMode.wholeTile,
    );
    if (filePath == null) return;
    final xmlString = await File(filePath).readAsString();
    final points = await parseGpxTrackPoints(xmlString);
    setState(() {
      if (!add) {
        _settings.trackPoints = points;
      } else {
        _settings.trackPoints += points;
      }
    });
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
        builder:
            (ctx) => AlertDialog(
              title: const Text("Maps in Cache"),
              content: Expanded(
                child: SingleChildScrollView(child: Text(buffer.toString())),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                  },
                  child: const Text("OK"),
                ),
              ],
            ),
      );
    }
  }

  // --- Build Method (Refactored UI) ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Application Settings')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Viewing Options',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),

            // Switch Settings Group
            ...[
              _buildSettingRow(
                title: 'Manual Entry Mode',
                value: _settings.isManualEnabled,
                onChanged: (value) {
                  setState(() {
                    _settings.isManualEnabled = value;
                  });
                },
              ),
              _buildSettingRow(
                title: 'Show GPX Track',
                value: _settings.showGPX,
                onChanged: (value) {
                  setState(() {
                    _settings.showGPX = value;
                  });
                },
              ),
              _buildSettingRow(
                title: 'Show Position Coordinates',
                value: _settings.showPosition,
                onChanged: (value) {
                  setState(() {
                    _settings.showPosition = value;
                  });
                },
              ),
              _buildSettingRow(
                title: 'Show Pan Controls',
                value: _settings.showPan,
                onChanged: (value) {
                  setState(() {
                    _settings.showPan = value;
                  });
                },
              ),
              _buildSettingRow(
                title: 'Show Altitude Reading',
                value: _settings.showAltitude,
                onChanged: (value) {
                  setState(() {
                    _settings.showAltitude = value;
                  });
                },
              ),
              _buildSettingRow(
                title: 'Direction Pointer Visible',
                value: _settings.isCompassPointerEnabled,
                onChanged: (value) {
                  setState(() {
                    _settings.isCompassPointerEnabled = value;
                  });
                },
              ),
            ],

            const Divider(height: 30),

            // Map Data Management Section
            Text(
              'Map Data Management',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 10),

            // GPX Loading Actions Group
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'GPX Track Management',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _loadGPX(add: false),
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Load GPX file'),
                        ),
                        const SizedBox(height: 5),
                        ElevatedButton.icon(
                          onPressed: () => _loadGPX(add: true),
                          icon: Icon(Icons.add_task),
                          label: const Text('Add GPX File'),
                        ),
                        const SizedBox(height: 5),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              _settings.trackPoints.clear();
                            });
                          },
                          icon: Icon(Icons.clear_all),
                          label: const Text('Clear GPX Data'),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: TextFormField(
                                initialValue: _settings.gpxSmallStep.toString(),
                                decoration: const InputDecoration(
                                  labelText: 'GPX Step Size',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    _settings.gpxSmallStep =
                                        value.isNotEmpty
                                            ? int.tryParse(value) ?? 5
                                            : 5;
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: TextFormField(
                                initialValue: _settings.gpxBigStep.toString(),
                                decoration: const InputDecoration(
                                  labelText: 'GPX Big Step Size',
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    _settings.gpxBigStep =
                                        value.isNotEmpty
                                            ? int.tryParse(value) ?? 10
                                            : 10;
                                    ;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // const SizedBox(height: 10),

            // Map Actions Group
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Map Data Operations',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _listMaps(),
                          icon: const Icon(Icons.list_outlined),
                          label: const Text('List Cached Maps'),
                        ),
                        const SizedBox(height: 5),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.import_export),
                          onPressed: () async {
                            _settings.csvFileToImport = await _selectCSVFile(
                              context,
                            );
                            if (context.mounted) {
                              // Pop logic is better handled by the calling widget,
                              // but keeping original flow for functional equivalence.
                              Navigator.of(context).pop();
                            }
                          },
                          label: const Text('Import Maps'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // const SizedBox(height: 20),

            // Calibration & Display Actions Group
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Calibration & Viewing',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder:
                                (context) => ShowMapScreen(settings: _settings),
                          ),
                        );
                      },
                      child: const Text('Display Map'),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder:
                                (context) =>
                                    MapCalibrationScreen(settings: _settings),
                          ),
                        );
                      },
                      child: const Text('Run Map Calibration'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Clear Cache Button (Critical Action)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10.0),
              child: ElevatedButton(
                onPressed: () {
                  _clearCache();
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text(
                  '🔥 Clear Entire Map Cache (Danger)',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),

            // const SizedBox(height: 20),

            // Done Button
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              spacing: 8.0,
              children: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to build standardized setting rows (Switches)
  Widget _buildSettingRow({
    required String title,
    required ValueChanged<bool> onChanged,
    required bool value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 16)),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
