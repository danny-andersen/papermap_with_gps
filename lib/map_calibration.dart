import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path/path.dart' as path;

import 'package:papermap_with_gps/common.dart';
import 'package:papermap_with_gps/gpxpainter.dart';

class MapCalibrationScreen extends StatefulWidget {
  final MapAppSettings settings;

  const MapCalibrationScreen({super.key, required this.settings});

  @override
  MapCalibrationScreenState createState() => MapCalibrationScreenState();
}

class MapCalibrationScreenState extends State<MapCalibrationScreen> {
  File? _imageFile;
  final GlobalKey _imageKey = GlobalKey();
  Position? _firstPoint;
  Offset? _firstOffset;
  Position? _secondPoint;
  Offset? _secondOffset;
  Offset? _testOffset;
  MapData? _currentMap;
  List<TrackPoint> _trackPoints = [];
  int _highlightedGPXpoint = 0;
  double? _width;
  double? _height;
  bool _canSelect = false;
  bool _canCalibrate = false;
  bool _canTest = false;
  bool _canSave = false;
  late MapAppSettings _settings;
  final TextEditingController _firstPointController = TextEditingController();
  final TextEditingController _secondPointController = TextEditingController();
  final TextEditingController _testPointController = TextEditingController();
  final TextEditingController _gpxPointController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
    // _firstPointController.addListener(() {
    //   _updatePointFromText(_firstPointController, isSecondPoint: false);
    // });
    // _secondPointController.addListener(() {
    //   _updatePointFromText(_secondPointController, isSecondPoint: true);
    // });
  }

  Future<void> _pickImage() async {
    String? image = await FilesystemPicker.openDialog(
      title: 'Pick a map file',
      context: context,
      rootDirectory: Directory(_settings.mapDir!),
      fsType: FilesystemType.file,
      allowedExtensions: ['.jpg', 'jpeg'],
      fileTileSelectMode: FileTileSelectMode.wholeTile,
    );
    if (image != null) {
      MapData? selectedMap;
      for (MapData map in _settings.mapFilesMetadata) {
        if (map.fileName == image) {
          selectedMap = map;
          break;
        }
      }
      setState(() {
        _reset();
        _currentMap = selectedMap;
        _imageFile = File(image);
      });
    }
  }

  void _calibrate() {
    //Using the selected points that have been updated, recalculate the top left and bottom right of the image
    RenderBox? imageRenderBox =
        _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (imageRenderBox != null) {
      Size size = imageRenderBox.size;
      _width = size.width;
      _height = size.height;
    }

    _updatePointFromText(_firstPointController, isSecondPoint: false);
    _updatePointFromText(_secondPointController, isSecondPoint: true);
    _currentMap!.calibrate(
      _firstPoint!,
      _firstOffset!.dx,
      _firstOffset!.dy,
      _secondPoint!,
      _secondOffset!.dx,
      _secondOffset!.dy,
      _width!,
      _height!,
    );
    setState(() {
      _canTest = true;
      _canSelect = false;
      _canSave = true;
    });
  }

  void _reset() {
    setState(() {
      _canSelect = true;
      _canCalibrate = false;
      _canTest = false;
      _firstOffset = null;
      _firstPoint = null;
      _secondOffset = null;
      _secondPoint = null;
      _testOffset = null;
      _firstPointController.clear();
      _secondPointController.clear();
      _testPointController.clear();
      _trackPoints.clear();
      _highlightedGPXpoint = 0;
    });
  }

  void _save() {
    MapData.saveMapData(_settings);
  }

  void _loadGPX() async {
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
      _trackPoints = points;
      _highlightedGPXpoint = 0;
    });
  }

  void _testPoint(Offset offset) {
    RenderBox? imageRenderBox =
        _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (imageRenderBox != null) {
      Size size = imageRenderBox.size;
      _width = size.width;
      _height = size.height;
    }

    setState(() {
      _testOffset = Offset(offset.dx, offset.dy);
      if (_currentMap != null) {
        Position testPos = _currentMap!.calculatePosition(
          _testOffset!.dx,
          _testOffset!.dy,
          _width!,
          _height!,
        );
        _testPointController.text =
            '${testPos.latitude.toStringAsFixed(6)}, ${testPos.longitude.toStringAsFixed(6)}';
      }
    });
  }

  void _setPoint(Offset offset) {
    RenderBox? imageRenderBox =
        _imageKey.currentContext?.findRenderObject() as RenderBox?;
    if (imageRenderBox != null) {
      Size size = imageRenderBox.size;
      _width = size.width;
      _height = size.height;
    }
    setState(() {
      if (_firstPoint == null || _secondPoint != null) {
        if (_currentMap != null) {
          _firstOffset = Offset(offset.dx, offset.dy);
          _firstPoint = _currentMap!.calculatePosition(
            offset.dx,
            offset.dy,
            _width!,
            _height!,
          );
          _firstPointController.text =
              '${_firstPoint!.latitude.toStringAsFixed(6)}, ${_firstPoint!.longitude.toStringAsFixed(6)}';
        }
        _secondPoint = null;
      } else if (_secondPoint == null) {
        if (_currentMap != null) {
          _secondOffset = Offset(offset.dx, offset.dy);
          _secondPoint = _currentMap!.calculatePosition(
            offset.dx,
            offset.dy,
            _width!,
            _height!,
          );
          _secondPointController.text =
              '${_secondPoint!.latitude.toStringAsFixed(6)}, ${_secondPoint!.longitude.toStringAsFixed(6)}';
          _canCalibrate = true;
        }
      }
    });
  }

  void _updatePointFromText(
    TextEditingController controller, {
    required bool isSecondPoint,
  }) {
    if (_canCalibrate) {
      final regex = RegExp(r'([^,]+), ([^,]+)');
      final match = regex.firstMatch(controller.text);
      if (match != null) {
        final lat = double.tryParse(match.group(1)!.trim());
        final long = double.tryParse(match.group(2)!.trim());
        if (lat != null && long != null) {
          final Position pos = Position(
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
          RenderBox? imageRenderBox =
              _imageKey.currentContext?.findRenderObject() as RenderBox?;
          if (imageRenderBox != null) {
            Size size = imageRenderBox.size;
            _width = size.width;
            _height = size.height;
          }
          double top = _currentMap!.calculateTop(_secondPoint!, _height!);
          double left = _currentMap!.calculateLeft(_secondPoint!, _width!);

          if (isSecondPoint) {
            setState(() {
              _secondPoint = pos;
              _secondOffset = Offset(left, top);
            });
          } else {
            setState(() {
              _firstPoint = pos;
              _firstOffset = Offset(left, top);
            });
          }
        }
      }
    }
  }

  void _updateGPXTextField() {
    final p = _trackPoints[_highlightedGPXpoint];
    _gpxPointController.text =
        '${p.lat.toStringAsFixed(6)}, ${p.lon.toStringAsFixed(6)}';
  }

  void _moveNextGPXPoint(int jump) {
    if (_highlightedGPXpoint < _trackPoints.length - jump) {
      setState(() {
        _highlightedGPXpoint += jump;
        _secondPoint = Position(
          latitude: _settings.trackPoints![_highlightedGPXpoint].lat,
          longitude: _settings.trackPoints![_highlightedGPXpoint].lon,
          timestamp: _settings.trackPoints![_highlightedGPXpoint].time,
          accuracy: 0.0,
          altitude: _settings.trackPoints![_highlightedGPXpoint].elevation,
          heading: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
          headingAccuracy: 0.0,
          altitudeAccuracy: 0.0,
        );
        RenderBox? imageRenderBox =
            _imageKey.currentContext?.findRenderObject() as RenderBox?;
        if (imageRenderBox != null) {
          Size size = imageRenderBox.size;
          _width = size.width;
          _height = size.height;
        }
        double top = _currentMap!.calculateTop(_secondPoint!, _height!);
        double left = _currentMap!.calculateLeft(_secondPoint!, _width!);

        _secondOffset = Offset(left, top);

        _updateGPXTextField();
      });
    }
  }

  void _movePreviousGPXPoint(int jump) {
    if (_highlightedGPXpoint > jump) {
      setState(() {
        _highlightedGPXpoint -= jump;
        _secondPoint = Position(
          latitude: _settings.trackPoints![_highlightedGPXpoint].lat,
          longitude: _settings.trackPoints![_highlightedGPXpoint].lon,
          timestamp: _settings.trackPoints![_highlightedGPXpoint].time,
          accuracy: 0.0,
          altitude: _settings.trackPoints![_highlightedGPXpoint].elevation,
          heading: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
          headingAccuracy: 0.0,
          altitudeAccuracy: 0.0,
        );
        RenderBox? imageRenderBox =
            _imageKey.currentContext?.findRenderObject() as RenderBox?;
        if (imageRenderBox != null) {
          Size size = imageRenderBox.size;
          _width = size.width;
          _height = size.height;
        }
        double top = _currentMap!.calculateTop(_secondPoint!, _height!);
        double left = _currentMap!.calculateLeft(_secondPoint!, _width!);

        _secondOffset = Offset(left, top);

        _updateGPXTextField();
      });
    }
  }

  Widget _showGPXTrail() {
    Widget retWidget = const SizedBox();
    if (_trackPoints.isNotEmpty && _currentMap != null) {
      RenderBox? imageRenderBox =
          _imageKey.currentContext?.findRenderObject() as RenderBox?;
      if (imageRenderBox != null) {
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
        retWidget = CustomPaint(
          size: Size(totalBoxSize.width, totalBoxSize.height),
          painter: GpxTrailPainter(
            points: _trackPoints,
            hightlightedPoint: _highlightedGPXpoint,
            imageWidth: totalBoxSize.width,
            imageHeight: totalBoxSize.height,
            mapData: _currentMap!,
          ),
        );
      }
    }
    return retWidget;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Map Calibrator ${_currentMap != null ? ': ${path.basename(File(_currentMap!.fileName).path)}' : " "}',
        ),
      ),
      body: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller: _firstPointController,
                    decoration: const InputDecoration(labelText: 'First Point'),
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _secondPointController,
                  decoration: const InputDecoration(labelText: 'Second Point'),
                ),
              ),
              if (_canTest) ...{
                Expanded(
                  child: TextField(
                    controller: _testPointController,
                    decoration: const InputDecoration(labelText: 'Test Point'),
                  ),
                ),
              },
              if (_trackPoints.isNotEmpty) ...{
                Expanded(
                  child: TextField(
                    controller: _gpxPointController,
                    decoration: const InputDecoration(labelText: 'GPX'),
                  ),
                ),
              },
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: ElevatedButton(
                  onPressed: _pickImage,
                  child: const Text('Choose a Map'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: ElevatedButton(
                  onPressed: _canCalibrate ? _calibrate : null,
                  child: const Text('Calibrate'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: ElevatedButton(
                  onPressed: _reset,
                  child: const Text('Reset'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: ElevatedButton(
                  onPressed: _canSave ? _save : null,
                  child: const Text('Save'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: ElevatedButton(
                  onPressed: _currentMap != null ? _loadGPX : null,
                  child: const Text('Load GPX file'),
                ),
              ),
            ],
          ),
          Expanded(
            child:
                _imageFile == null
                    ? const Center(child: Text('No Map selected.'))
                    : LayoutBuilder(
                      builder: (context, constraints) {
                        _width = constraints.maxWidth;
                        _height = constraints.maxHeight;
                        return Focus(
                          autofocus: true,
                          onKeyEvent: (node, event) {
                            if (event is KeyDownEvent) {
                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowRight) {
                                _moveNextGPXPoint(5);
                              } else if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowDown) {
                                _moveNextGPXPoint(30);
                              } else if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowLeft) {
                                _movePreviousGPXPoint(5);
                              } else if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowUp) {
                                _movePreviousGPXPoint(30);
                              }
                            }
                            return KeyEventResult.handled;
                          },
                          child: GestureDetector(
                            onTapDown: (details) {
                              if (_canSelect) {
                                _setPoint(details.localPosition);
                              } else if (_canTest) {
                                _testPoint(details.localPosition);
                              }
                            },
                            child: Stack(
                              children: [
                                Image.file(
                                  key: _imageKey,
                                  _imageFile!,
                                  cacheWidth: constraints.maxWidth.toInt() * 4,
                                  cacheHeight:
                                      constraints.maxHeight.toInt() * 4,
                                  fit: BoxFit.contain,
                                ),
                                if (_firstOffset != null)
                                  Positioned(
                                    left: _firstOffset!.dx - 12,
                                    top: _firstOffset!.dy - 24,
                                    child: const Icon(
                                      Icons.location_on,
                                      color: Colors.red,
                                      size: 24,
                                    ),
                                  ),
                                if (_secondOffset != null)
                                  Positioned(
                                    left: _secondOffset!.dx - 12,
                                    top: _secondOffset!.dy - 24,
                                    child: const Icon(
                                      Icons.location_on,
                                      color: Colors.blue,
                                      size: 24,
                                    ),
                                  ),
                                if (_testOffset != null)
                                  Positioned(
                                    left: _testOffset!.dx - 12,
                                    top: _testOffset!.dy - 24,
                                    child: const Icon(
                                      Icons.location_on,
                                      color: Colors.green,
                                      size: 24,
                                    ),
                                  ),
                                _showGPXTrail(),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}
