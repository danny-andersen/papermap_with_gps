import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:papermap_with_gps/common.dart';

class GpxTrailPainter extends CustomPainter {
  final List<TrackPoint> points;
  final int hightlightedPoint;
  final double imageWidth;
  final double imageHeight;
  final MapData mapData;

  GpxTrailPainter({
    required this.points,
    required this.hightlightedPoint,
    required this.imageWidth,
    required this.imageHeight,
    required this.mapData,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.fill;

    final paintHighlighted =
        Paint()
          ..color = Colors.blue
          ..style = PaintingStyle.fill;

    int index = -1;

    for (final TrackPoint p in points) {
      final pos = Position(
        latitude: p.lat,
        longitude: p.lon,
        timestamp: p.time,
        accuracy: 0.0,
        altitude: p.elevation,
        heading: 0.0,
        speed: 0.0,
        speedAccuracy: 0.0,
        headingAccuracy: 0.0,
        altitudeAccuracy: 0.0,
      );
      index++;

      // Only draw if the point is inside the map bounds
      if (!mapData.isPointOnMap(pos)) continue;

      final top = mapData.calculateTop(pos, imageHeight);
      final left = mapData.calculateLeft(pos, imageWidth);

      if (top >= 0 && left >= 0) {
        if (index == hightlightedPoint && hightlightedPoint != 0) {
          //Dont show the current marker position until the position has been set
          canvas.drawCircle(Offset(left, top), 3.0, paintHighlighted);
        } else {
          canvas.drawCircle(Offset(left, top), 2.0, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
