import 'dart:math';
import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:path/path.dart' as path;
import 'package:csv/csv.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

enum PanDirection { left, right, up, down }

class MapAppSettings {
  static const String mapCsvFile = 'mapdata.csv';
  static const String localMapDir = 'papermaps';
  static const String defaultMapAssetName = 'assets/maps/general-map.jpg';

  bool isManualEnabled = false;
  bool isCompassPointerEnabled = false;
  bool showPosition = false;
  bool showPan = true;
  bool showAltitude = true;
  String? csvFileToImport;
  String? mapDir;
  List<MapData> mapFilesMetadata = List.empty(growable: true);
  late MapData defaultMap;
  MapAppSettings(manual) {
    isManualEnabled = manual;
  }

  static Future<Directory> getRootDirectory() async {
    Directory? rootdir;
    try {
      if (await Permission.manageExternalStorage.request().isGranted) {
        rootdir = await getExternalStorageDirectory();
        //If we get to here, we are on an Android device, so set the Doc directory manually
        rootdir = Directory('/storage/emulated/0/Documents');
      } else {
        print("Failed to get permission to manage external storage");
      }
    } catch (e) {
      print("Failed to get external storage directory, trying docs: $e");
      // exceptionStr = e.toString();
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
        '"Filename", "TopLeftLat", "TopLeftLong", "BotRightLat", "BotRightLon", "Quality"');
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
    final File cacheCsvFile =
        File(path.join(settings.mapDir!, MapAppSettings.mapCsvFile));
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
      bool withinLatBounds = (point.latitude <= topLeft.latitude &&
          point.latitude >= bottomRight.latitude);
      bool withinLonBounds = (point.longitude >= topLeft.longitude &&
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
      bool leftMostEdge = bottomRight.longitude >=
          (map.topLeft.longitude - allowedLongitudeRange);
      bool rightMostEdge = (bottomRight.longitude <= map.bottomRight.longitude);
      //Check latitude overlap
      bool topEdge = bottomRight.latitude <= map.topLeft.latitude &&
          bottomRight.latitude >= map.bottomRight.latitude;
      bool bottomEdge = topLeft.latitude >= map.bottomRight.latitude &&
          topLeft.latitude <= map.topLeft.latitude;
      bool completeOverlap = topLeft.latitude >= map.topLeft.latitude &&
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
      bool rightMostEdge = topLeft.longitude <=
          (map.bottomRight.longitude + allowedLongitudeRange);
      //Check latitude overlap
      bool topEdge = bottomRight.latitude <= map.topLeft.latitude &&
          bottomRight.latitude >= map.bottomRight.latitude;
      bool bottomEdge = topLeft.latitude >= map.bottomRight.latitude &&
          topLeft.latitude <= map.topLeft.latitude;
      bool completeOverlap = topLeft.latitude >= map.topLeft.latitude &&
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
      bool leftMostEdge = bottomRight.longitude >= map.topLeft.longitude &&
          bottomRight.longitude <= map.bottomRight.longitude;
      bool rightMostEdge = map.bottomRight.longitude >= topLeft.longitude &&
          topLeft.longitude >= map.topLeft.longitude;
      bool completeOverlap = topLeft.longitude <= map.topLeft.longitude &&
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
      bool leftMostEdge = bottomRight.longitude >= map.topLeft.longitude &&
          bottomRight.longitude <= map.bottomRight.longitude;
      bool rightMostEdge = map.bottomRight.longitude >= topLeft.longitude &&
          topLeft.longitude >= map.topLeft.longitude;
      bool completeOverlap = topLeft.longitude <= map.topLeft.longitude &&
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
      double x, double y, double imageWidth, double imageHeight) {
    final double latitude = bottomRight.latitude +
        ((1 - (y / imageHeight)) * (topLeft.latitude - bottomRight.latitude));
    final double longitude = topLeft.longitude +
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

  void calibrate(Position topL, double tlx, double tly, Position bottomR,
      double brx, double bry, double width, double height) {
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
  double a = pow(sin(dLat / 2), 2) +
      cos(degreesToRadians(lat1)) *
          cos(degreesToRadians(lat2)) *
          pow(sin(dLon / 2), 2);
  double c = 2 * atan2(sqrt(a), sqrt(1 - a));

  // Calculate the distance
  double distance = earthRadius * c;

  return distance;
}
