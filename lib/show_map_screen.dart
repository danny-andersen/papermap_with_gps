import 'dart:io';

import 'package:flutter/material.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path/path.dart' as path;

import 'package:papermap_with_gps/common.dart';
import 'package:papermap_with_gps/gpxpainter.dart';

class ShowMapScreen extends StatefulWidget {
  final MapAppSettings settings;

  const ShowMapScreen({super.key, required this.settings});

  @override
  ShowMapScreenState createState() => ShowMapScreenState(settings: settings);
}

class ShowMapScreenState extends State<ShowMapScreen> {
  ShowMapScreenState({required MapAppSettings settings}) : _settings = settings;
  final MapAppSettings _settings;
  File? _imageFile;
  final GlobalKey _imageKey = GlobalKey();
  Position? _firstPoint;
  Offset? _firstOffset;
  Position? _secondPoint;
  Offset? _secondOffset;
  MapData? _currentMap;
  List<TrackPoint> _trackPoints = [];
  int _highlightedGPXpoint = 0;
  double _distance = 0.0;
  double? _width;
  double? _height;
  final TextEditingController _firstPointController = TextEditingController();
  final TextEditingController _secondPointController = TextEditingController();

  @override
  void initState() {
    super.initState();
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
        _currentMap = selectedMap;
        _imageFile = File(image);
      });
      _setPointOffsets();
    }
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
    if (_firstPoint == null || _secondPoint != null) {
      _firstOffset = Offset(offset.dx, offset.dy);
      _firstPoint = _currentMap!.calculatePosition(
        _firstOffset!.dx,
        _firstOffset!.dy,
        _width!,
        _height!,
      );
      _secondPoint = null;
      _secondOffset = null;
      _distance = 0.0;
      _secondPointController.text = "";
      _highlightedGPXpoint = 0;
    } else if (_secondPoint == null) {
      _secondOffset = Offset(offset.dx, offset.dy);
      if (_secondOffset != null) {
        _secondPoint = _currentMap!.calculatePosition(
          _secondOffset!.dx,
          _secondOffset!.dy,
          _width!,
          _height!,
        );
        _highlightedGPXpoint = 0;
      }
    }
    if (_currentMap != null) {
      setState(() {
        if (_firstPoint != null) {
          _firstPointController.text =
              '${_firstPoint!.latitude.toStringAsFixed(6)}, ${_firstPoint!.longitude.toStringAsFixed(6)}';
        }
        if (_secondPoint != null) {
          _secondPointController.text =
              '${_secondPoint!.latitude.toStringAsFixed(6)}, ${_secondPoint!.longitude.toStringAsFixed(6)}';
        }
        if (_firstPoint != null && _secondPoint != null) {
          _distance = calculateDistance(
            _secondPoint!.latitude,
            _secondPoint!.longitude,
            _firstPoint!.latitude,
            _firstPoint!.longitude,
          );
        }
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

  void _setPointOffsets() {
    //Calculates new icon offsets when map is updated based on the lat long previously set
    if (_currentMap != null) {
      RenderBox? imageRenderBox =
          _imageKey.currentContext?.findRenderObject() as RenderBox?;
      if (imageRenderBox != null) {
        //Get size of the painted box
        // Offset totalBoxSize = imageRenderBox.paintBounds.bottomRight;
        Size totalBoxSize = imageRenderBox.size;
        if (_firstPoint != null) {
          double top = _currentMap!.calculateTop(
            _firstPoint!,
            totalBoxSize.height,
          );
          double left = _currentMap!.calculateLeft(
            _firstPoint!,
            totalBoxSize.width,
          );
          setState(() {
            _firstOffset = Offset(left, top);
          });
        }
        if (_secondPoint != null) {
          double top = _currentMap!.calculateTop(
            _secondPoint!,
            totalBoxSize.height,
          );
          double left = _currentMap!.calculateLeft(
            _secondPoint!,
            totalBoxSize.width,
          );
          setState(() {
            _secondOffset = Offset(left, top);
          });
        }
      }
    }
  }

  Widget _buildInfoBoxes() {
    // Determine whether to position the altitude box at the top or bottom right
    bool isTopQuarter = false;
    if (_distance != 0) {
      RenderBox? imageRenderBox =
          _imageKey.currentContext?.findRenderObject() as RenderBox?;
      if (imageRenderBox == null) return const SizedBox();

      //Get size of the painted box
      // Offset totalBoxSize = imageRenderBox.paintBounds.bottomRight;
      Size totalBoxSize = imageRenderBox.size;
      isTopQuarter =
          _currentMap!.calculateTop(_firstPoint!, totalBoxSize.height) <
          (totalBoxSize.height / 4);
    }
    double distInfoPos =
        (_settings.showAltitude && !_settings.isManualEnabled) ? 40 : 5;

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
                'Altitude: ${_firstPoint?.altitude.toStringAsFixed(2)} m',
                style: const TextStyle(color: Colors.white, fontSize: 16),
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
                '${_highlightedGPXpoint != 0 ? "GPX" : ""} Distance: ${_distance.toStringAsFixed(2)} km',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        },
      ],
    );
  }

  void _moveNextGPXPoint(int jump) {
    if (_highlightedGPXpoint == 0) {
      //Find nearest point on the track to the current GPS position
      if (_secondPoint != null) {
        _highlightedGPXpoint = getNearestPointIndex(_trackPoints, _firstPoint);
      }
    }
    if (_highlightedGPXpoint < _trackPoints.length - jump) {
      RenderBox? imageRenderBox =
          _imageKey.currentContext?.findRenderObject() as RenderBox?;
      if (imageRenderBox != null) {
        Size size = imageRenderBox.size;
        _width = size.width;
        _height = size.height;
      }
      setState(() {
        _highlightedGPXpoint += jump;
        _secondPoint = Position(
          latitude: _trackPoints![_highlightedGPXpoint].lat,
          longitude: _trackPoints![_highlightedGPXpoint].lon,
          timestamp: _trackPoints![_highlightedGPXpoint].time,
          accuracy: 0.0,
          altitude: _trackPoints![_highlightedGPXpoint].elevation,
          heading: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
          headingAccuracy: 0.0,
          altitudeAccuracy: 0.0,
        );
        _secondPointController.text =
            '${_secondPoint!.latitude.toStringAsFixed(6)}, ${_secondPoint!.longitude.toStringAsFixed(6)}';

        double top = _currentMap!.calculateTop(_secondPoint!, _height!);
        double left = _currentMap!.calculateLeft(_secondPoint!, _width!);

        _secondOffset = Offset(left, top);

        _distance = calculateDistanceBasedOnGpx(
          _trackPoints,
          _firstPoint,
          _highlightedGPXpoint,
        );
      });
    }
  }

  void _movePreviousGPXPoint(int jump) {
    if (_highlightedGPXpoint > jump) {
      RenderBox? imageRenderBox =
          _imageKey.currentContext?.findRenderObject() as RenderBox?;
      if (imageRenderBox != null) {
        Size size = imageRenderBox.size;
        _width = size.width;
        _height = size.height;
      }

      setState(() {
        _highlightedGPXpoint -= jump;
        _secondPoint = Position(
          latitude: _trackPoints![_highlightedGPXpoint].lat,
          longitude: _trackPoints![_highlightedGPXpoint].lon,
          timestamp: _trackPoints![_highlightedGPXpoint].time,
          accuracy: 0.0,
          altitude: _trackPoints![_highlightedGPXpoint].elevation,
          heading: 0.0,
          speed: 0.0,
          speedAccuracy: 0.0,
          headingAccuracy: 0.0,
          altitudeAccuracy: 0.0,
        );
        _secondPointController.text =
            '${_secondPoint!.latitude.toStringAsFixed(6)}, ${_secondPoint!.longitude.toStringAsFixed(6)}';
        double top = _currentMap!.calculateTop(_secondPoint!, _height!);
        double left = _currentMap!.calculateLeft(_secondPoint!, _width!);

        _secondOffset = Offset(left, top);

        _distance = calculateDistanceBasedOnGpx(
          _trackPoints,
          _firstPoint,
          _highlightedGPXpoint,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Show Map ${_currentMap != null ? ': ${path.basename(File(_currentMap!.fileName).path)}' : " "}',
        ),
      ),
      body: Column(
        spacing: 0.0,
        children: [
          if (_trackPoints.isNotEmpty) ...{
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8.0, 0.0, 5.0, 0.0),
                  child: Text(
                    'GPX Point Move:',
                    style: const TextStyle(color: Colors.black),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.fast_rewind),
                  tooltip: 'GPX Back ${_settings.gpxBigStep}',
                  onPressed: () {
                    setState(() {
                      _movePreviousGPXPoint(_settings.gpxBigStep);
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_left),
                  tooltip: 'GPX Move Back ${_settings.gpxSmallStep}',
                  onPressed: () {
                    setState(() {
                      _movePreviousGPXPoint(_settings.gpxSmallStep);
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_right),
                  tooltip: 'GPX Move Forward ${_settings.gpxSmallStep}',
                  onPressed: () {
                    setState(() {
                      _moveNextGPXPoint(_settings.gpxSmallStep);
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.fast_forward),
                  tooltip: 'GPX Forward ${_settings.gpxBigStep}',
                  onPressed: () {
                    setState(() {
                      _moveNextGPXPoint(_settings.gpxBigStep);
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.location_on, color: Colors.blue),
                  tooltip: 'GPX nearest selected point',
                  onPressed: () {
                    setState(() {
                      _highlightedGPXpoint = getNearestPointIndex(
                        _trackPoints,
                        _secondPoint,
                      );
                      _moveNextGPXPoint(0);
                    });
                  },
                ),
              ],
            ),
          },
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8.0, 0.0, 5.0, 0.0),
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
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8.0, 0.0, 5.0, 0.0),
                child: ElevatedButton(
                  onPressed: _pickImage,
                  child: const Text('Choose Map'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: ElevatedButton(
                  onPressed: _currentMap != null ? _loadGPX : null,
                  child: const Text('Load GPX'),
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
                          child: GestureDetector(
                            onTapDown: (details) {
                              _setPoint(details.localPosition);
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
                                _showGPXTrail(),
                                _buildInfoBoxes(),
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
