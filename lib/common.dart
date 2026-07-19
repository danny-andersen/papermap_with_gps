import 'dart:math';
import 'dart:io';
import 'package:xml/xml.dart';

import 'package:geolocator/geolocator.dart';
import 'package:latlong_to_osgrid/latlong_to_osgrid.dart';
import 'package:path/path.dart' as path;
import 'package:csv/csv.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

enum PanDirection { left, right, up, down }

class TrackPoint {
  final double lat;
  final double lon;
  final double elevation;
  final DateTime time;

  TrackPoint({
    required this.lat,
    required this.lon,
    required this.elevation,
    required this.time,
  });

  @override
  String toString() =>
      'TrackPoint(lat: $lat, lon: $lon, ele: $elevation, time: $time)';
}

final LatLongConverter _latLongConverter = LatLongConverter();

Future<List<TrackPoint>> parseGpxTrackPoints(String gpxXml) async {
  final document = XmlDocument.parse(gpxXml);

  final trkpts = document.findAllElements('trkpt', namespaceUri: '*');

  final points = <TrackPoint>[];

  for (final pt in trkpts) {
    final lat = double.parse(pt.getAttribute('lat')!);
    final lon = double.parse(pt.getAttribute('lon')!);

    final eleElement = pt.getElement('ele', namespaceUri: '*');
    final timeElement = pt.getElement('time', namespaceUri: '*');

    final elevation = eleElement != null ? double.parse(eleElement.text) : 0.0;
    final time =
        timeElement != null ? DateTime.parse(timeElement.text) : DateTime.now();

    points.add(
      TrackPoint(lat: lat, lon: lon, elevation: elevation, time: time),
    );
  }

  return points;
}

class MapAppSettings {
  static const String mapCsvFile = 'mapdata.csv';
  static const String localMapDir = 'papermaps';
  static const String defaultMapAssetName = 'assets/generalmap.png';

  bool isManualEnabled = false;
  bool isCompassPointerEnabled = false;
  bool showPosition = false;
  bool showPan = true;
  bool showAltitude = true;
  bool showGPX = true;
  String? csvFileToImport;
  String? mapDir;
  List<MapData> mapFilesMetadata = List.empty(growable: true);
  late MapData defaultMap;
  MapAppSettings(manual) {
    isManualEnabled = manual;
  }
  List<TrackPoint> trackPoints = [];
  int gpxSmallStep = 5;
  int gpxBigStep = 10;

  static Future<String> setMapDir() async {
    Directory dir = await getApplicationDirectory();
    String destdirectory = path.join(dir.path, MapAppSettings.localMapDir);
    await Directory(destdirectory).create(recursive: true);
    return destdirectory;
  }

  static Future<Directory> getApplicationDirectory() async {
    Directory? appDir;
    if (Platform.isAndroid) {
      try {
        if (await Permission.manageExternalStorage.request().isGranted) {
          appDir = await getExternalStorageDirectory();
        } else {
          print("Failed to get permission to manage external storage");
        }
      } catch (e) {
        print("Failed to get external storage directory, trying docs: $e");
        // exceptionStr = e.toString();
      }
    }
    appDir ??= await getApplicationDocumentsDirectory();
    return appDir;
  }

  static Future<Directory> getRootDirectory() async {
    Directory? rootdir;
    if (Platform.isAndroid) {
      if (await Permission.manageExternalStorage.request().isGranted) {
        // rootdir = await getDownloadsDirectory();
        //If we get to here and directory is null, set the Doc directory manually
        // print('Root dir = $rootdir');
        rootdir = Directory('/storage/emulated/0/Documents');
      } else {
        print("Failed to get permission to manage external storage");
      }
    }
    rootdir ??= await getApplicationDocumentsDirectory();
    return rootdir;
  }
}

class MapData {
  late String fileName;
  late Position topLeft;
  late Position bottomRight;
  int quality = -1;
  double _area = -1;
  MapData? mapLeft;
  MapData? mapRight;
  MapData? mapAbove;
  MapData? mapBelow;

  static const double _degreesToKilometers =
      111.0; // approximate conversion for latitude

  static MapData? getByFilename(List<MapData> maps, String filename) {
    MapData? returnVal;
    for (MapData map in maps) {
      if (map.fileName == filename) {
        returnVal = map;
        break;
      }
    }
    return returnVal;
  }

  static int saveMapData(MapAppSettings settings) {
    //Create the new csv meta file from the new list of MapData
    const csvCreator = ListToCsvConverter();
    StringBuffer sb = StringBuffer();
    sb.writeln(
      '"Filename", "TopLeftLat", "TopLeftLong", "BotRightLat", "BotRightLon", "Quality"',
    );
    int totalMaps = 0;
    for (MapData map in settings.mapFilesMetadata) {
      csvCreator.convertSingleRow(
        sb,
        map.getAttrs(),
        textEndDelimiter: '\r\n',
        returnString: false,
      );
      sb.writeln();
      totalMaps++;
    }
    //Write new csv file
    final File cacheCsvFile = File(
      path.join(settings.mapDir!, MapAppSettings.mapCsvFile),
    );
    cacheCsvFile.writeAsStringSync(sb.toString(), flush: true);
    return totalMaps;
  }

  MapData(this.fileName, this.topLeft, this.bottomRight);

  MapData.fromAttrs(List<dynamic> attrs) {
    fileName = attrs[0];
    topLeft = Position(
      latitude: attrs[1],
      longitude: attrs[2],
      timestamp: DateTime.now(),
      accuracy: 0.0,
      altitude: 0.0,
      heading: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      headingAccuracy: 0.0,
      altitudeAccuracy: 0.0,
    );
    bottomRight = Position(
      latitude: attrs[3],
      longitude: attrs[4],
      timestamp: DateTime.now(),
      accuracy: 0.0,
      altitude: 0.0,
      heading: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      headingAccuracy: 0.0,
      altitudeAccuracy: 0.0,
    );
    quality = attrs[5];
  }

  // filename, top left lat, top left long, bottom right lat, bottom right long, quality
  List<dynamic> getAttrs() {
    List<dynamic> attrs = List.empty(growable: true);
    attrs.add(fileName);
    attrs.add(topLeft.latitude);
    attrs.add(topLeft.longitude);
    attrs.add(bottomRight.latitude);
    attrs.add(bottomRight.longitude);
    attrs.add(quality);
    return attrs;
  }

  double getArea({bool force = false}) {
    if (force) {
      _area = -1;
    }
    if (_area == -1) {
      // Calculate the absolute differences in latitude and longitude
      double latDiff = (topLeft.latitude - bottomRight.latitude).abs();
      double lonDiff = (topLeft.longitude - bottomRight.longitude).abs();

      // Convert latitude difference to kilometers
      double latDistance = latDiff * _degreesToKilometers;

      // Average latitude for more accurate longitude conversion
      double avgLat = (topLeft.latitude + bottomRight.latitude) / 2.0;
      double lonDistance =
          lonDiff * _degreesToKilometers * cos(avgLat * pi / 180);

      // Calculate the area in square kilometers
      _area = latDistance * lonDistance;
    }

    return _area;
  }

  bool isPointOnMap(Position? point) {
    bool result = false;

    if (point != null) {
      bool withinLatBounds =
          (point.latitude <= topLeft.latitude &&
              point.latitude >= bottomRight.latitude);
      bool withinLonBounds =
          (point.longitude >= topLeft.longitude &&
              point.longitude <= bottomRight.longitude);

      result = withinLatBounds && withinLonBounds;
    }
    return result;
  }

  double isLeftOf(MapData map) {
    double retVal = 0;
    if (map.quality == quality) {
      double allowedLongitudeRange =
          (map.topLeft.longitude - map.bottomRight.longitude).abs() / 2;
      bool leftMostEdge =
          bottomRight.longitude >=
          (map.topLeft.longitude - allowedLongitudeRange);
      bool rightMostEdge = (bottomRight.longitude <= map.bottomRight.longitude);
      //Check latitude overlap
      bool topEdge =
          bottomRight.latitude <= map.topLeft.latitude &&
          bottomRight.latitude >= map.bottomRight.latitude;
      bool bottomEdge =
          topLeft.latitude >= map.bottomRight.latitude &&
          topLeft.latitude <= map.topLeft.latitude;
      bool completeOverlap =
          topLeft.latitude >= map.topLeft.latitude &&
          bottomRight.latitude <= map.bottomRight.latitude;
      if (leftMostEdge &&
          rightMostEdge &&
          (topEdge || bottomEdge || completeOverlap)) {
        //Return value is amount of overlap in latitude
        if (completeOverlap) {
          retVal = map.bottomRight.latitude - map.topLeft.latitude;
        } else {
          double overlap1 = 0;
          double overlap2 = 0;
          if (topEdge) {
            overlap1 = map.topLeft.latitude - bottomRight.latitude;
          }

          if (bottomEdge) {
            overlap2 = topLeft.latitude - map.bottomRight.latitude;
          }
          if (overlap1 > overlap2) {
            retVal = overlap1;
          } else {
            retVal = overlap2;
          }
        }
      }
    }
    return retVal;
  }

  double isRightOf(MapData map) {
    double retVal = 0;
    if (map.quality == quality) {
      double allowedLongitudeRange =
          (map.topLeft.longitude - map.bottomRight.longitude).abs() / 2;
      bool leftMostEdge = topLeft.longitude >= map.topLeft.longitude;
      bool rightMostEdge =
          topLeft.longitude <=
          (map.bottomRight.longitude + allowedLongitudeRange);
      //Check latitude overlap
      bool topEdge =
          bottomRight.latitude <= map.topLeft.latitude &&
          bottomRight.latitude >= map.bottomRight.latitude;
      bool bottomEdge =
          topLeft.latitude >= map.bottomRight.latitude &&
          topLeft.latitude <= map.topLeft.latitude;
      bool completeOverlap =
          topLeft.latitude >= map.topLeft.latitude &&
          bottomRight.latitude <= map.bottomRight.latitude;
      if (leftMostEdge &&
          rightMostEdge &&
          (topEdge || bottomEdge || completeOverlap)) {
        //Return value is amount of overlap in latitude
        if (completeOverlap) {
          retVal = map.bottomRight.latitude - map.topLeft.latitude;
        } else {
          //Return value is amount of overlap in latitude
          double overlap1 = 0;
          double overlap2 = 0;
          if (topEdge) {
            overlap1 = map.topLeft.latitude - bottomRight.latitude;
          }
          if (bottomEdge) {
            overlap2 = topLeft.latitude - map.bottomRight.latitude;
          }
          if (overlap1 > overlap2) {
            retVal = overlap1;
          } else {
            retVal = overlap2;
          }
        }
      }
    }
    return retVal;
  }

  double isAbove(MapData map) {
    double retVal = 0;
    if (map.quality == quality) {
      double allowedLatitudeRange =
          (map.topLeft.latitude - map.bottomRight.latitude).abs() / 2;
      bool leftMostEdge =
          bottomRight.longitude >= map.topLeft.longitude &&
          bottomRight.longitude <= map.bottomRight.longitude;
      bool rightMostEdge =
          map.bottomRight.longitude >= topLeft.longitude &&
          topLeft.longitude >= map.topLeft.longitude;
      bool completeOverlap =
          topLeft.longitude <= map.topLeft.longitude &&
          bottomRight.longitude >= map.bottomRight.longitude;
      bool lowerEdge = bottomRight.latitude >= map.bottomRight.latitude;
      bool upperEdge =
          bottomRight.latitude <= (map.topLeft.latitude + allowedLatitudeRange);
      if ((leftMostEdge || rightMostEdge || completeOverlap) &&
          lowerEdge &&
          upperEdge) {
        //Return value is amount of overlap in longitude
        if (completeOverlap) {
          retVal = map.bottomRight.longitude - map.topLeft.longitude;
        } else {
          double val1 = 0;
          double val2 = 0;
          if (leftMostEdge) {
            val1 = bottomRight.longitude - map.topLeft.longitude;
          }
          if (rightMostEdge) {
            val2 = map.bottomRight.longitude - topLeft.longitude;
          }
          if (val1 > val2) {
            retVal = val1;
          } else {
            retVal = val2;
          }
        }
      }
    }
    return retVal;
  }

  double isBelow(MapData map) {
    double retVal = 0;
    if (map.quality == quality) {
      double allowedLatitudeRange =
          (map.topLeft.latitude - map.bottomRight.latitude).abs() / 2;
      bool leftMostEdge =
          bottomRight.longitude >= map.topLeft.longitude &&
          bottomRight.longitude <= map.bottomRight.longitude;
      bool rightMostEdge =
          map.bottomRight.longitude >= topLeft.longitude &&
          topLeft.longitude >= map.topLeft.longitude;
      bool completeOverlap =
          topLeft.longitude <= map.topLeft.longitude &&
          bottomRight.longitude >= map.bottomRight.longitude;
      bool lowerEdge =
          topLeft.latitude >= (map.bottomRight.latitude - allowedLatitudeRange);
      bool upperEdge = topLeft.latitude <= map.topLeft.latitude;
      if ((leftMostEdge || rightMostEdge || completeOverlap) &&
          lowerEdge &&
          upperEdge) {
        //Return value is amount of overlap in longitude
        if (completeOverlap) {
          retVal = map.bottomRight.longitude - map.topLeft.longitude;
        } else {
          double val1 = 0;
          double val2 = 0;
          if (leftMostEdge) {
            val1 = bottomRight.longitude - map.topLeft.longitude;
          }
          if (rightMostEdge) {
            val2 = map.bottomRight.longitude - topLeft.longitude;
          }
          if (val1 > val2) {
            retVal = val1;
          } else {
            retVal = val2;
          }
        }
      }
    }
    return retVal;
  }

  double calculateTop(Position position, double imageHeight) {
    double top = -1;
    if (position.latitude <= topLeft.latitude &&
        position.latitude >= bottomRight.latitude) {
      final double latRange = topLeft.latitude - bottomRight.latitude;
      final double latOffset =
          1 - ((position.latitude - bottomRight.latitude) / latRange);
      top = latOffset * imageHeight;
    }
    return top;
  }

  double calculateLeft(Position position, double imageWidth) {
    double left = -1;
    if (position.longitude >= topLeft.longitude &&
        position.longitude <= bottomRight.longitude) {
      final double longRange = bottomRight.longitude - topLeft.longitude;
      final double longOffset =
          (position.longitude - topLeft.longitude) / longRange;
      left = longOffset * imageWidth;
    }
    return left;
  }

  Position calculatePosition(
    double x,
    double y,
    double imageWidth,
    double imageHeight,
  ) {
    final double latitude =
        bottomRight.latitude +
        ((1 - (y / imageHeight)) * (topLeft.latitude - bottomRight.latitude));
    final double longitude =
        topLeft.longitude +
        ((x / imageWidth) * (bottomRight.longitude - topLeft.longitude));
    return Position(
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.now(),
      accuracy: 0.0,
      altitude: 0.0,
      heading: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      headingAccuracy: 0.0,
      altitudeAccuracy: 0.0,
    );
  }

  void calibrate(
    Position topL,
    double tlx,
    double tly,
    Position bottomR,
    double brx,
    double bry,
    double width,
    double height,
  ) {
    double calwidth = brx - tlx;
    double calheight = bry - tly;
    double calLatrange = topL.latitude - bottomR.latitude;
    double calLongrange = bottomR.longitude - topL.longitude;
    //Calculate the corresponding lat long of 0,0
    final double zeroLat = topL.latitude + (calLatrange * tly / calheight);
    final double zeroLong = topL.longitude - (calLongrange * tlx / calwidth);
    topLeft = Position(
      latitude: zeroLat,
      longitude: zeroLong,
      timestamp: DateTime.now(),
      accuracy: 0.0,
      altitude: 0.0,
      heading: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      headingAccuracy: 0.0,
      altitudeAccuracy: 0.0,
    );
    //Calculate bottom right
    final double botLat =
        bottomR.latitude - (calLatrange * (height - bry) / calheight);
    final double botLong =
        bottomR.longitude + (calLongrange * (width - brx) / calwidth);
    bottomRight = Position(
      latitude: botLat,
      longitude: botLong,
      timestamp: DateTime.now(),
      accuracy: 0.0,
      altitude: 0.0,
      heading: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      headingAccuracy: 0.0,
      altitudeAccuracy: 0.0,
    );
  }

  //Return true if this map is better than the one passed in
  //Criteria:
  // 1. If Quality is higher then a better map
  // 2. Or if area covered (size) is smaller and quality is the same
  // 3. If the quality is the same, and area covered similar, but the current location is more central
  bool isBetterMap(MapData otherMap, Position? location) {
    bool result = false;
    bool moreCentral = false;
    if (location != null) {
      double topdev = (50 - calculateTop(location, 100)).abs();
      double leftdev = (50 - calculateLeft(location, 100)).abs();
      double topOtherDev = (50 - otherMap.calculateTop(location, 100)).abs();
      double leftOtherDev = (50 - otherMap.calculateLeft(location, 100)).abs();
      double variance = topdev + leftdev;
      double varOther = topOtherDev + leftOtherDev;
      if (variance < varOther) {
        moreCentral = true;
      }
    }
    double areaRatio = getArea() / otherMap.getArea();

    if (quality > otherMap.quality) {
      result = true;
    }
    if (areaRatio < 1 && quality == otherMap.quality) {
      //Same quality but this map covers a smaller area
      result = true;
    }
    if (areaRatio < 3 && quality < otherMap.quality) {
      //Lesser quality but this map covers a much smaller area
      result = true;
    }
    if (areaRatio < 1.5 && quality == otherMap.quality && moreCentral) {
      //Same qualityand similar size but this map shows current location more in the centre
      result = true;
    }

    return result;
  }

  MapData.world() {
    fileName = "DefaultMap";
    topLeft = Position(
      latitude: 103.33230238911,
      longitude: -183.871077302632,
      timestamp: DateTime.now(),
      accuracy: 0.0,
      altitude: 0.0,
      heading: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      headingAccuracy: 0.0,
      altitudeAccuracy: 0.0,
    );
    bottomRight = Position(
      latitude: -102.257386576812,
      longitude: 182.546373058711,
      timestamp: DateTime.now(),
      accuracy: 0.0,
      altitude: 0.0,
      heading: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      headingAccuracy: 0.0,
      altitudeAccuracy: 0.0,
    );
    quality = 0;
    _area = getArea();
  }

  MapData.fromFileName(this.fileName) {
    final name = fileName.split('/').last.split('.jpg').first;
    final coordinates = name.split('@');
    final topLeft = coordinates[0].split('+');
    final bottomRight = coordinates[1].split('+');

    this.topLeft = Position(
      latitude: double.parse(topLeft[1]),
      longitude: double.parse(topLeft[0]),
      timestamp: DateTime.now(),
      accuracy: 0.0,
      altitude: 0.0,
      heading: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      headingAccuracy: 0.0,
      altitudeAccuracy: 0.0,
    );
    this.bottomRight = Position(
      latitude: double.parse(bottomRight[1]),
      longitude: double.parse(bottomRight[0]),
      timestamp: DateTime.now(),
      accuracy: 0.0,
      altitude: 0.0,
      heading: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      headingAccuracy: 0.0,
      altitudeAccuracy: 0.0,
    );
  }
}

//If in deg, mins and secs convert to digital degrees
//If already in dig degress, just parse the double

double? convertToDecimalDegrees(String coord) {
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

// Function to convert degrees to radians
double degreesToRadians(double degrees) {
  return degrees * pi / 180;
}

// Function to calculate the distance between two points using Haversine formula
double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  const double earthRadius = 6371.0; // Radius of Earth in kilometers

  // Convert latitude and longitude from degrees to radians
  double dLat = degreesToRadians(lat2 - lat1);
  double dLon = degreesToRadians(lon2 - lon1);

  // Apply Haversine formula
  double a =
      pow(sin(dLat / 2), 2) +
      cos(degreesToRadians(lat1)) *
          cos(degreesToRadians(lat2)) *
          pow(sin(dLon / 2), 2);
  double c = 2 * atan2(sqrt(a), sqrt(1 - a));

  // Calculate the distance
  double distance = earthRadius * c;

  return distance;
}

//
// Calculates the distance between the current GPS location and the nearest
// or currently selected GPX point on the track.
//
double calculateDistanceBasedOnGpx(
  List<TrackPoint> trackPoints,
  Position? currentPosition,
  int highlightedGPXpoint,
) {
  if (currentPosition == null || trackPoints.isEmpty) {
    // If no position or no points, distance remains 0 (or handled by old logic)
    return 0.0;
  }

  double distanceToPoint = 0.0;

  //Find the nearest point on the track to the current GPS position
  int nearestPointIndex = getNearestPointIndex(trackPoints, currentPosition);
  //Add in the distance between the current position and the nearest GPX point on the track
  distanceToPoint += calculateDistance(
    currentPosition.latitude,
    currentPosition.longitude,
    trackPoints[nearestPointIndex].lat,
    trackPoints[nearestPointIndex].lon,
  );
  if (highlightedGPXpoint >= 0) {
    // Distance from nearest GPX point to the selected GPX point
    distanceToPoint += totalDistanceBetween(
      trackPoints,
      nearestPointIndex,
      highlightedGPXpoint,
    );
  }

  return distanceToPoint;
}

/// Computes the total distance (in meters) between two indices
/// in a list of TrackPoint objects.
double totalDistanceBetween(
  List<TrackPoint> points,
  int startIndex,
  int endIndex,
) {
  if (startIndex < 0 || endIndex >= points.length) {
    return 0.0;
  }

  if (startIndex >= endIndex) {
    int temp = startIndex;
    startIndex = endIndex;
    endIndex = temp;
  }
  double total = 0.0;

  for (int i = startIndex; i < endIndex; i++) {
    total += calculateDistance(
      points[i].lat,
      points[i].lon,
      points[i + 1].lat,
      points[i + 1].lon,
    );
  }

  return total;
}

int getNearestPointIndex(List<TrackPoint> points, Position? currentPosition) {
  double minDistance = double.infinity;
  int nearestIndex = 0;

  if (points.isEmpty || currentPosition == null) {
    return nearestIndex;
  }

  for (int i = 0; i < points.length; i++) {
    double distance = calculateDistance(
      currentPosition.latitude,
      currentPosition.longitude,
      points[i].lat,
      points[i].lon,
    );

    if (distance < minDistance) {
      minDistance = distance;
      nearestIndex = i;
    }
  }

  return nearestIndex;
}

// Calculates altitude gain between two points (positive change)
(double, double) calculateAltitudeChange(
  List<TrackPoint> points, {
  int? startIndex,
  int? endIndex,
}) {
  // double gain = 0.0;
  // double loss = 0.0;
  int start = startIndex ?? 0;
  int end = endIndex ?? points.length - 1;

  if (start > end) {
    final temp = start;
    start = end;
    end = temp;
  }
  // for (int i = start + 1; i <= end; i++) {
  //   final currentAltitude = points[i].elevation;
  //   final previousAltitude = points[i - 1].elevation;

  //   if (currentAltitude > previousAltitude) {
  //     gain += currentAltitude - previousAltitude;
  //   } else if (currentAltitude < previousAltitude) {
  //     loss += previousAltitude - currentAltitude;
  //   }
  // }

  return calculateAltitudeStats(points.sublist(start, end + 1));
}

/// Main function: smoothing + threshold + gain/loss
(double, double) calculateAltitudeStats(
  List<TrackPoint> points, {
  int smoothingWindow = 7,
  double minDelta = 2.0,
}) {
  if (points.length < 2) {
    return (0, 0);
  }

  // 1. Extract raw altitude series
  final raw = points.map((p) => p.elevation).toList();

  // 2. Smooth altitude using Savitzky–Golay filter
  final smoothed = _savitzkyGolay(raw, smoothingWindow);

  // 3. Compute gain/loss with threshold
  double gain = 0.0;
  double loss = 0.0;

  for (int i = 1; i < smoothed.length; i++) {
    final delta = smoothed[i] - smoothed[i - 1];

    if (delta.abs() < minDelta) {
      // Ignore tiny noise fluctuations
      continue;
    }

    if (delta > 0) {
      gain += delta;
    } else {
      loss += -delta;
    }
  }

  return (gain, loss);
}

/// Savitzky–Golay smoothing (polynomial order 2)
List<double> _savitzkyGolay(List<double> data, int windowSize) {
  if (windowSize.isEven || windowSize < 5) {
    throw ArgumentError("windowSize must be odd and >= 5");
  }

  final half = windowSize ~/ 2;
  final smoothed = List<double>.filled(data.length, 0);

  for (int i = 0; i < data.length; i++) {
    double acc = 0;
    double weightSum = 0;

    for (int j = -half; j <= half; j++) {
      final idx = (i + j).clamp(0, data.length - 1);
      final w = _sgWeight(j, half);
      acc += data[idx] * w;
      weightSum += w;
    }

    smoothed[i] = acc / weightSum;
  }

  return smoothed;
}

/// Precomputed Savitzky–Golay weights for polynomial order 2
double _sgWeight(int k, int halfWindow) {
  // For simplicity, use a quadratic SG kernel:
  // w(k) = 1 - (k^2 / (halfWindow^2))
  return 1 - (k * k) / (halfWindow * halfWindow);
}
