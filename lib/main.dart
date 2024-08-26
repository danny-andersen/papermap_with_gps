import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;

// import 'package:image_size_getter/image_size_getter.dart';
// import 'package:image_size_getter/file_input.dart'; // For compatibility with flutter web.
import 'package:csv/csv_settings_autodetection.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong_to_osgrid/latlong_to_osgrid.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
import 'package:flutter_compass/flutter_compass.dart';

import 'package:papermap_with_gps/common.dart';
import 'package:papermap_with_gps/settings_screen.dart';

void main() => runApp(const MaterialApp(home: MyApp()));

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  MyAppState createState() => MyAppState();
}

class MyAppState extends State<MyApp> {
  Position? _currentPosition;
  Position? _selectedPosition;
  Offset? _selectedPoint;
  double _distance = 0;
  final TextEditingController _positionController = TextEditingController();
  final GlobalKey _imageKey = GlobalKey();
  final MapAppSettings _settings = MapAppSettings(false);
  late List<MapData> _currentMaps;
  MapData? _panMap;
  int _currentMapIndex = 0;
  // TransformationController _transformationController =
  //     TransformationController();
  final LatLongConverter _latLongConverter = LatLongConverter();
  late Timer gpsUpdateTimer;

  @override
  void initState() {
    super.initState();
    _settings.defaultMap = MapData.world();
    _loadCachedMapFiles();
    _currentMaps = [_settings.defaultMap];
    _turnOnRefresh();
  }

  @override
  void dispose() {
    _turnOffRefresh();
    super.dispose();
  }

  void _turnOnRefresh() {
    Future.delayed(
        const Duration(seconds: 2),
        () => setState(() {
              _getCurrentLocation();
            }));
    gpsUpdateTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      setState(() {
        _getCurrentLocation();
      });
    });
  }

  void _turnOffRefresh() {
    gpsUpdateTimer.cancel();
  }

  Future<void> _importCSVFile(BuildContext context, String? csvfile) async {
    if (csvfile != null) {
      if (_settings.mapDir == null) {
        Directory dir = await getApplicationDocumentsDirectory();
        String destdirectory = path.join(dir.path, MapAppSettings.localMapDir);
        await Directory(destdirectory).create(recursive: true);
        _settings.mapDir = destdirectory;
      }
      //Now process the new csv file and add the entries into the existing one
      //copying and new or updated map files at the same time.
      File file = File(csvfile);
      String sourceDir = path.dirname(csvfile);
      final csvinput = file.openRead();
      const settings = FirstOccurrenceSettingsDetector(
          eols: ['\r\n', '\n'], textDelimiters: ['"', "'"]);

      final fields = await csvinput
          .transform(utf8.decoder)
          .transform(const CsvToListConverter(csvSettingsDetector: settings))
          .toList();

      // CSV file has a row for each map file
      // filename, top left lat, top left long, bottom right lat, bottom right long, quality
      // Quality = 0 is least detail, 5 is highest detail
      // first row is header row - ignore
      bool firstRow = true;
      int importedMaps = 0;
      for (var row in fields) {
        if (firstRow) {
          firstRow = false;
          continue;
        }
        if (row.length >= 6) {
          MapData mapData = MapData.fromAttrs(row);
          String destPath = path.join(_settings.mapDir!, mapData.fileName);

          // Copy the file to the application directory if it exists
          File sourceFile = File(path.join(sourceDir, mapData.fileName));
          try {
            // if (await sourceFile.existsSync()) {
            await sourceFile.copy(destPath);
            // print("Copied $sourceFile to $destPath");
            importedMaps++;
            //Set filename to full path
            mapData.fileName = destPath;
            //Add or replace CSV entry for existing CSV file held in user directory, if it exists
            MapData? existingMap = MapData.getByFilename(
                _settings.mapFilesMetadata, mapData.fileName);
            if (existingMap == null) {
              _settings.mapFilesMetadata.add(mapData);
            } else {
              //replace attributes
              existingMap.topLeft = mapData.topLeft;
              existingMap.bottomRight = mapData.bottomRight;
              existingMap.quality = mapData.quality;
              existingMap.getArea(force: true);
            }
            // } else {
            //   print('File ${path.join(sourceFile.path)} does not exist');
            // }
          } catch (e) {
            // print('Failed to copy File ${path.join(sourceFile.path)} $e');
            if (context.mounted) {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("Failed to copy map"),
                  content:
                      Text("${path.join(sourceDir, mapData.fileName)}: $e"),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                      },
                      child: Container(
                        color: Colors.green,
                        padding: const EdgeInsets.all(14),
                        child: const Text("OK"),
                      ),
                    ),
                  ],
                ),
              );
            }
            // print(
            //     'Failed to copy file ${path.join(sourceDir, mapData.fileName)}: $e');
          }
        }
      }
      int totalMaps = MapData.saveMapData(_settings);
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("New map metafile created"),
            content: Text(
                "Maps Imported: $importedMaps\nTotal maps now stored: $totalMaps"),
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
      // }
      // print("Written new cache metafile $destdirectory/$mapCsvFile");
      //Set bordering maps for each map loaded
      for (MapData map in _settings.mapFilesMetadata) {
        _setBorderingMaps(map);
      }
    } else {
      // User cancelled the picker
    }
  }

  Future<void> _loadCachedMapFiles() async {
    //Process CSV file holding details of maps held in application cache
    if (_settings.mapDir == null) {
      Directory dir = await MapAppSettings.getRootDirectory();
      String destdirectory = path.join(dir.path, MapAppSettings.localMapDir);
      await Directory(destdirectory).create(recursive: true);
      _settings.mapDir = destdirectory;
    }
    File cacheCsvFile =
        File("${_settings.mapDir}/${MapAppSettings.mapCsvFile}");
    if (await cacheCsvFile.exists()) {
      final cacheCsv = cacheCsvFile.openRead();
      const settings = FirstOccurrenceSettingsDetector(
          eols: ['\r\n', '\n'], textDelimiters: ['"', "'"]);

      List cacheFields = await cacheCsv
          .transform(utf8.decoder)
          .transform(const CsvToListConverter(csvSettingsDetector: settings))
          .toList();
      bool firstRow = true;
      for (var row in cacheFields) {
        if (firstRow) {
          firstRow = false;
          continue;
        }
        MapData mapData = MapData.fromAttrs(row);
        //Check file exists and if does then load it
        File mapFile = File(mapData.fileName);
        if (mapFile.existsSync()) {
          _settings.mapFilesMetadata.add(mapData);
        }
      }
    }
    //Set bordering maps for each map loaded
    for (MapData map in _settings.mapFilesMetadata) {
      _setBorderingMaps(map);
    }
  }

  //Choose the best map based on the following criteria:
  //1. Point is inside the map boundary
  //2. And map has a higher quality than the current map
  //2 (b). If the same quality, current location is closer to the centre
  //3. Or map has a smaller size
  void _getBestMaps() {
    int prevMaps = _currentMaps.length;
    MapData prevMap = _currentMaps[_currentMapIndex];
    _currentMaps.clear();
    _currentMaps.add(_settings.defaultMap);
    if (_currentPosition != null) {
      for (MapData map in _settings.mapFilesMetadata) {
        if (map.isPointOnMap(_currentPosition!)) {
          //Valid map - put in the current list based on the best map
          int mapIndex = 0;
          bool inserted = false;
          for (MapData validMap in _currentMaps) {
            if (map.isBetterMap(validMap, _currentPosition)) {
              //This map is better than the one at this index - insert here
              _currentMaps.insert(mapIndex, map);
              inserted = true;
              break;
            }
            mapIndex++;
          }
          if (!inserted) {
            //Not as good as the existing ones - add at the end
            _currentMaps.add(map);
          }
        }
      }
    }
    if (prevMaps != _currentMaps.length) {
      //If number of valid maps has changed, reset the index to the best one
      _currentMapIndex = 0;
    }
    if (_currentMaps[_currentMapIndex] != prevMap) {
      _setBorderingMaps(_currentMaps[_currentMapIndex]);
    }
  }

  void _setBorderingMaps(MapData mapToSet) {
    //Now find maps that border this one
    mapToSet.mapLeft = null;
    mapToSet.mapRight = null;
    mapToSet.mapAbove = null;
    mapToSet.mapBelow = null;
    double leftOverlap = 0;
    double rightOverlap = 0;
    double aboveOverlap = 0;
    double belowOverlap = 0;
    if (mapToSet.fileName != "DefaultMap") {
      for (MapData map in _settings.mapFilesMetadata) {
        if (map == mapToSet) continue;
        double overlap = map.isLeftOf(mapToSet);
        if (overlap > 0) {
          if (mapToSet.mapLeft == null) {
            mapToSet.mapLeft = map;
            leftOverlap = overlap;
          } else if (leftOverlap < overlap) {
            //Map overlaps more
            mapToSet.mapLeft = map;
            leftOverlap = overlap;
          }
        }
        overlap = map.isRightOf(mapToSet);
        if (overlap > 0) {
          if (mapToSet.mapRight == null) {
            mapToSet.mapRight = map;
            rightOverlap = overlap;
          } else if (rightOverlap < overlap) {
            //Map overlaps more
            mapToSet.mapRight = map;
            rightOverlap = overlap;
          }
        }
        overlap = map.isAbove(mapToSet);
        if (overlap > 0) {
          if (mapToSet.mapAbove == null) {
            mapToSet.mapAbove = map;
            aboveOverlap = overlap;
          } else if (aboveOverlap < overlap) {
            mapToSet.mapAbove = map;
            aboveOverlap = overlap;
          }
        }
        overlap = map.isBelow(mapToSet);
        if (overlap > 0) {
          if (mapToSet.mapBelow == null) {
            mapToSet.mapBelow = map;
            belowOverlap = overlap;
          } else if (belowOverlap < overlap) {
            mapToSet.mapBelow = map;
            belowOverlap = overlap;
          }
        }
      }
    }
  }

  _setPoint(MapData mapOnShow, Offset offset) {
    RenderBox? imageRenderBox =
        _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (imageRenderBox == null) return;
    Size imageSize = imageRenderBox.size;
    _selectedPoint = offset;
    setState(() {
      _selectedPosition = mapOnShow.calculatePosition(
          offset.dx, offset.dy, imageSize.width, imageSize.height);
      if (_currentPosition != null && _selectedPosition != null) {
        _distance = calculateDistance(
            _currentPosition!.latitude,
            _currentPosition!.longitude,
            _selectedPosition!.latitude,
            _selectedPosition!.longitude);
      }
    });
  }

  _getCurrentLocation() async {
    if (_settings.isManualEnabled) {
      setState(() {
        _updatePosition();
        _getBestMaps();
      });
    } else {
      //Use GPS if available
      try {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          throw Exception('Location services are disabled.');
        }

        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
          if (permission == LocationPermission.denied) {
            throw Exception('Location permissions are denied.');
          }
        }

        if (permission == LocationPermission.deniedForever) {
          throw Exception('Location permissions are permanently denied.');
        }

        Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high)
            .then((Position position) {
          setState(() {
            _currentPosition = position;
            if (_selectedPosition != null) {
              _distance = calculateDistance(
                  _currentPosition!.latitude,
                  _currentPosition!.longitude,
                  _selectedPosition!.latitude,
                  _selectedPosition!.longitude);
            }
            _getBestMaps();
            _positionController.text =
                "${position.latitude.toString()},${position.longitude.toString()}";
          });
        });
      } catch (e) {
        if (mounted) {
          setState(() {
            _settings.isManualEnabled = true;
          });
          _showGPSFailureDialog(
              "Failed to retrieve GPS coords ${e.toString()}");
        }
      }
    }
    if (_selectedPosition != null && _selectedPoint == null) {
      RenderBox? imageRenderBox =
          _imageKey.currentContext?.findRenderObject() as RenderBox?;
      if (imageRenderBox == null) return;
      Size imageSize = imageRenderBox.size;
      double top = _currentMaps[_currentMapIndex]
          .calculateTop(_selectedPosition!, imageSize.height);
      double left = _currentMaps[_currentMapIndex]
          .calculateLeft(_selectedPosition!, imageSize.width);
      if (mounted) {
        setState(() {
          _selectedPoint = Offset(left, top);
        });
      }
    }
  }

  void _updatePosition() {
    // final double? latitude, longitude;

    final regex = RegExp(r'([^,]+),([^,]+)');
    final match = regex.firstMatch(_positionController.text);
    if (match != null) {
      final lat = double.tryParse(match.group(1)!.trim());
      final long = double.tryParse(match.group(2)!.trim());
      if (lat != null && long != null) {
        _currentPosition = Position(
          latitude: lat,
          longitude: long,
          timestamp: DateTime.now(),
          accuracy: 0.0,
          altitude: 0.0,
          heading: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
          headingAccuracy: 0.0,
          altitudeAccuracy: 0.0,
        );
        if (_selectedPosition != null) {
          _distance = calculateDistance(
              _currentPosition!.latitude,
              _currentPosition!.longitude,
              _selectedPosition!.latitude,
              _selectedPosition!.longitude);
        }
      }
    }
  }

  void _showGPSFailureDialog(String message) {
    try {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Error'),
            content: Text(message),
            actions: <Widget>[
              TextButton(
                child: const Text('OK'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    } catch (e) {
      print(e);
    }
  }

  //If in deg, mins and secs convert to digital degrees
  //If already in dig degress, just parse the double

  double? _convertToDecimalDegrees(String coord) {
    // Extract the direction (N/S/E/W)
    String direction = coord.substring(coord.length - 1);
    coord = coord.substring(0, coord.length - 1);

    // Split into degrees, minutes, and seconds
    RegExp regex = RegExp(r'''(\d+)°(\d+)\'(\d+(\.\d+)?)\"''');
    Match? match = regex.firstMatch(coord);

    if (match == null) {
      throw const FormatException("Invalid coordinate format");
    }

    // Parse the degrees, minutes, and seconds
    double? degrees = double.tryParse(match.group(1)!);
    double? minutes = double.tryParse(match.group(2)!);
    double? seconds = double.tryParse(match.group(3)!);

    // Convert to decimal degrees
    double? decimalDegrees;
    if (degrees != null && minutes != null && seconds != null) {
      decimalDegrees = degrees + (minutes / 60) + (seconds / 3600);
      // Adjust for direction
      if (direction == 'S' || direction == 'W') {
        decimalDegrees *= -1;
      }
    }

    return decimalDegrees;
  }

  (double, double) convertOSToLatLon(int easting, int northing) {
    LatLong result = _latLongConverter.getLatLongFromOSGB(easting, northing);
    return (result.lat, result.long);
  }

  Widget _buildSetPointIcon(MapData currentMap) {
    Widget? retWidget;
    if (_selectedPosition != null &&
        currentMap.isPointOnMap(_selectedPosition)) {
      RenderBox? imageRenderBox =
          _imageKey.currentContext?.findRenderObject() as RenderBox?;
      if (imageRenderBox != null) {
        //Get size of the painted box
        // Offset totalBoxSize = imageRenderBox.paintBounds.bottomRight;
        Size totalBoxSize = imageRenderBox.size;
        double top =
            currentMap.calculateTop(_selectedPosition!, totalBoxSize.height);
        double left =
            currentMap.calculateLeft(_selectedPosition!, totalBoxSize.width);

        _selectedPoint = Offset(left, top);
        retWidget = Positioned(
          left: _selectedPoint!.dx - 20,
          top: _selectedPoint!.dy - 40,
          child: const Icon(
            Icons.location_on,
            color: Colors.blue,
            size: 40,
          ),
        );
      }
    }
    return retWidget ?? const SizedBox();
  }

  Widget _buildFixedIcon(MapData currentMap) {
    if (!currentMap.isPointOnMap(_currentPosition)) return const SizedBox();
    RenderBox? imageRenderBox =
        _imageKey.currentContext?.findRenderObject() as RenderBox?;
    late Widget retWidget;
    if (imageRenderBox == null) return const SizedBox();

    //Get size of the painted box
    // Offset totalBoxSize = imageRenderBox.paintBounds.bottomRight;
    Size totalBoxSize = imageRenderBox.size;
    // Coordinates of the fixed point on the original image
    // double top = _calculateTop(_currentPosition!, totalBoxSize.dy);
    // double left = _calculateLeft(_currentPosition!, totalBoxSize.dx);
    // if (_settings.isManualEnabled) {
    //   //Get latest position coords before displaying
    //   _updatePosition();
    // }
    if (_currentPosition != null) {
      double top =
          currentMap.calculateTop(_currentPosition!, totalBoxSize.height);
      double left =
          currentMap.calculateLeft(_currentPosition!, totalBoxSize.width);

      Offset fixedPoint = Offset(left, top);

      // print(
      //     "Lat: ${_currentPosition!.latitude}  Long: ${_currentPosition!.longitude}");

      if (_settings.isCompassPointerEnabled && !_settings.isManualEnabled) {
        const double iconSize = 30.0;
        double adjustedLeft = fixedPoint.dx - iconSize / 2;
        double adjustedTop = fixedPoint.dy - iconSize / 2;
        retWidget = Positioned(
          left: adjustedLeft,
          top: adjustedTop,
          child: StreamBuilder<CompassEvent?>(
            stream: FlutterCompass.events,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                _settings.isCompassPointerEnabled = false;
                return Text("Error reading heading: ${snapshot.error}");
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const CircularProgressIndicator();
              }

              double? direction = snapshot.data!.heading;
              // If direction is null, then the device doesn't have a compass sensor
              if (direction == null) {
                _settings.isCompassPointerEnabled = false;
                return const Text("No compass sensor found");
              }
              return Transform.rotate(
                angle: (direction * (math.pi / 180)),
                child: const Icon(
                  Icons.arrow_upward,
                  size: iconSize,
                  color: Colors.red,
                ),
              );
            },
          ),
        );
      } else {
        double iconSize = 40;
        double adjustedLeft = fixedPoint.dx - iconSize / 2;
        double adjustedTop = fixedPoint.dy - iconSize;
        retWidget = Positioned(
          left: adjustedLeft,
          top: adjustedTop,
          child: Icon(
            // Icons.arrow_drop_up,
            // color: Colors.red,
            // size: 50,
            Icons.location_on,
            color: Colors.red,
            size: iconSize,
          ),
        );
      }
    } else {
      retWidget = Positioned(
        left: totalBoxSize.width / 2,
        top: totalBoxSize.height / 2,
        child: const Icon(
          // Icons.arrow_drop_up,
          // color: Colors.red,
          // size: 50,
          Icons.question_mark,
          color: Colors.red,
          size: 50,
        ),
      );
    }
    return retWidget;
  }

  @override
  Widget build(BuildContext context) {
    MapData mapToShow = _panMap ?? _currentMaps[_currentMapIndex];
    return MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Paper Maps'),
            actions: [
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () {
                      setState(() {
                        _getCurrentLocation();
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      setState(() {
                        _selectedPosition = null;
                        _selectedPoint = null;
                        _distance = 0;
                        _panMap = null;
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: _currentMapIndex < _currentMaps.length - 1
                        ? () {
                            setState(() {
                              _currentMapIndex++;
                            });
                            Future.delayed(const Duration(milliseconds: 1500),
                                _getCurrentLocation);
                          }
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_downward),
                    onPressed: _currentMapIndex > 0
                        ? () {
                            setState(() {
                              _currentMapIndex--;
                            });
                            Future.delayed(const Duration(milliseconds: 1500),
                                _getCurrentLocation);
                          }
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings),
                    onPressed: () async {
                      _settings.csvFileToImport = null;
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (context) =>
                                SettingsScreen(settings: _settings)),
                      );
                      setState(() {
                        if (_settings.csvFileToImport != null) {
                          Future.delayed(
                              const Duration(seconds: 1),
                              () => _importCSVFile(
                                  context, _settings.csvFileToImport));
                        }
                      });
                    },
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              if (_settings.isManualEnabled) ...[
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller: _positionController,
                    keyboardType: TextInputType.text,
                    decoration: const InputDecoration(
                        labelText:
                            'Enter Manual Position (Latitude,Longitude)'),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _getCurrentLocation();
                    });
                  },
                  child: const Text('Update Position'),
                ),
              ],
              if (_settings.showPosition) ...{
                Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        _currentPosition != null
                            ? '${_currentPosition!.latitude.toStringAsFixed(6)},${_currentPosition!.longitude.toStringAsFixed(6)}'
                            : "Not Set",
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                          _selectedPosition != null
                              ? '${_selectedPosition!.latitude.toStringAsFixed(6)},${_selectedPosition!.longitude.toStringAsFixed(6)}'
                              : '',
                          style: const TextStyle(color: Colors.blue)),
                    ),
                    if (_distance != 0) ...{
                      Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text('Dist: ${_distance.toStringAsFixed(2)} km',
                            style: const TextStyle(color: Colors.green)),
                      ),
                    },
                  ],
                )
              },
              Expanded(
                child:
                    //  _currentPosition == null
                    //       ? Center(child: CircularProgressIndicator())
                    //       :
                    LayoutBuilder(builder: (context, constraints) {
                  return Center(
                      child: GestureDetector(
                    onTapDown: (details) {
                      _setPoint(mapToShow, details.localPosition);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: InteractiveViewer(
                      // transformationController: _transformationController,
                      // boundaryMargin: EdgeInsets.all(20.0),
                      minScale: 0.1,
                      maxScale: 4.0,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned(
                            key: _imageKey,
                            top: 0,
                            left: 0,
                            child: Container(
                              constraints: BoxConstraints(
                                  maxWidth: constraints.maxWidth,
                                  maxHeight: constraints.maxHeight),
                              child: mapToShow.fileName != "DefaultMap"
                                  ? Image.file(File(mapToShow.fileName),
                                      // width: constraints.maxWidth,
                                      // height: constraints.maxHeight,
                                      cacheWidth:
                                          constraints.maxWidth.toInt() * 4,
                                      cacheHeight:
                                          constraints.maxHeight.toInt() * 4,
                                      fit: BoxFit.contain)
                                  : Image.asset(
                                      MapAppSettings.defaultMapAssetName,
                                      // width: constraints.maxWidth,
                                      // height: constraints.maxHeight,
                                      // cacheWidth:
                                      //     constraints.maxWidth.toInt() * 4,
                                      // cacheHeight:
                                      //     constraints.maxHeight.toInt() * 4,
                                      fit: BoxFit.contain),
                            ),
                          ),
                          _buildFixedIcon(mapToShow),
                          _buildSetPointIcon(mapToShow),
                          _buildInfoBoxes(mapToShow),
                        ],
                      ),
                    ),
                  ));
                }),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoBoxes(MapData currentMap) {
    // Determine whether to position the altitude box at the top or bottom right
    bool isTopQuarter = false;
    if (_currentPosition != null && currentMap.isPointOnMap(_currentPosition)) {
      RenderBox? imageRenderBox =
          _imageKey.currentContext?.findRenderObject() as RenderBox?;
      if (imageRenderBox == null) return const SizedBox();

      //Get size of the painted box
      // Offset totalBoxSize = imageRenderBox.paintBounds.bottomRight;
      Size totalBoxSize = imageRenderBox.size;
      isTopQuarter = _currentMaps[_currentMapIndex]
              .calculateTop(_currentPosition!, totalBoxSize.height) <
          (totalBoxSize.height / 4);
    }
    double distInfoPos =
        (_settings.showAltitude && !_settings.isManualEnabled) ? 40 : 5;
    double panOffset = _distance != 0
        ? (_settings.showAltitude && !_settings.isManualEnabled
            ? (distInfoPos * 2) - 5
            : (distInfoPos * 2) + 30)
        : distInfoPos;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_settings.showAltitude && !_settings.isManualEnabled) ...{
          Positioned(
            top: isTopQuarter ? null : 5,
            bottom: isTopQuarter ? 5 : null,
            right: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                'Altitude: ${_currentPosition?.altitude.toStringAsFixed(2)} m',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        },
        if (_distance != 0) ...{
          Positioned(
            top: isTopQuarter ? null : distInfoPos,
            bottom: isTopQuarter ? distInfoPos : null,
            right: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                'Distance: ${_distance.toStringAsFixed(2)} km',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        },
        if (_settings.showPan) ...{
          _buildArrowButtons(currentMap, isTopQuarter ? null : panOffset,
              isTopQuarter ? panOffset : null),
        },
      ],
    );
  }

  Widget _buildArrowButtons(
      MapData currentMap, double? topSep, double? bottomSep) {
    return Positioned(
      top: topSep,
      bottom: bottomSep,
      right: 5,
      child: GestureDetector(
        onTap: () {
          // Absorb the tap event so it doesn't propagate to the parent GestureDetector
        },
        behavior: HitTestBehavior.translucent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.5),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildArrowButton(currentMap, Icons.arrow_circle_up,
                      currentMap.mapAbove != null, PanDirection.up),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildArrowButton(currentMap, Icons.arrow_circle_left,
                      currentMap.mapLeft != null, PanDirection.left),
                  const SizedBox(width: 5),
                  _buildArrowButton(currentMap, Icons.arrow_circle_right,
                      currentMap.mapRight != null, PanDirection.right),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildArrowButton(currentMap, Icons.arrow_circle_down,
                      currentMap.mapBelow != null, PanDirection.down),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildArrowButton(MapData currentMap, IconData icon, bool isEnabled,
      PanDirection arrowPressed) {
    return IgnorePointer(
      ignoring: false,
      child: IconButton(
        icon: Icon(icon),
        iconSize: 35,
        color: isEnabled ? Colors.white : Colors.grey,
        onPressed: isEnabled
            ? () => _handleArrowPress(currentMap, arrowPressed)
            : null,
      ),
    );
  }

  void _handleArrowPress(MapData currentMap, PanDirection arrow) {
    // Implement logic for handling arrow button presses here
    if (arrow == PanDirection.left) {
      setState(() {
        _panMap = currentMap.mapLeft;
      });
    }
    if (arrow == PanDirection.right) {
      setState(() {
        _panMap = currentMap.mapRight;
      });
    }
    if (arrow == PanDirection.up) {
      setState(() {
        _panMap = currentMap.mapAbove;
      });
    }
    if (arrow == PanDirection.down) {
      setState(() {
        _panMap = currentMap.mapBelow;
      });
    }
  }
}
