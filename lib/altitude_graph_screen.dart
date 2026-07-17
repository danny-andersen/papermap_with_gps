import 'package:flutter/material.dart';
import 'dart:math';
// Import the charting library
import 'package:fl_chart/fl_chart.dart';
// Assuming TrackPoint definition is available, perhaps in lib/common.dart or a model file
import 'package:papermap_with_gps/common.dart'; // Replace with actual module name where CommonUtils resides
import 'package:geolocator/geolocator.dart';

class AltitudeGraphScreen extends StatelessWidget {
  final List<TrackPoint> trackPoints;
  final int? pointAIndex; // Index for the starting point marker (Red)
  final int? pointBIndex; // Index for the ending point marker (Blue)

  const AltitudeGraphScreen({
    Key? key,
    required this.trackPoints,
    this.pointAIndex,
    this.pointBIndex,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 1. Process the data to get (Distance, Altitude) pairs
    int startIndex =
        pointAIndex ?? 0; // Default to the first point if not provided
    int endIndex =
        pointBIndex ?? trackPoints.length - 1; // Default to the last point
    final (double altitudeGain, double altitudeLoss) = calculateAltitudeChange(
      trackPoints,
      startIndex: startIndex,
      endIndex: endIndex,
    );

    final (
      double altitudeGainTotal,
      double altitudeLossTotal,
    ) = calculateAltitudeChange(trackPoints);

    final List<(double distance, double altitude)> graphData =
        calculateAltitudeVsDistance(trackPoints);
    final currentPosition = Position(
      latitude: trackPoints[startIndex].lat,
      longitude: trackPoints[startIndex].lon,
      timestamp: DateTime.now(),
      accuracy: 0.0,
      altitude: trackPoints[startIndex].elevation,
      heading: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
      headingAccuracy: 0.0,
      altitudeAccuracy: 0.0,
    );
    final spots =
        graphData
            .map((item) => FlSpot(item.$1.toDouble(), item.$2.toDouble()))
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Altitude vs Distance Travelled'),
        backgroundColor: Colors.blueGrey,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            // Replaced the placeholder Container with fl_chart LineChartWidget
            SizedBox(
              height: 300,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  minY: ((_minAltitude(spots) - 100) / 100).floor() * 100,
                  maxY: ((_maxAltitude(spots) + 100) / 100).ceil() * 100,
                  // The data points for the line chart.
                  // We use a list of ScatterPointModel, mapping (Distance, Altitude) to Chart X/Y coordinates.
                  lineBarsData: [
                    LineChartBarData(
                      isCurved: true,
                      color: Colors.blue,
                      barWidth: 3,
                      dotData: const FlDotData(show: false),

                      spots: spots,
                    ),
                  ],
                  extraLinesData: ExtraLinesData(
                    verticalLines: [
                      VerticalLine(
                        x:
                            spots[startIndex]
                                .x, // X-axis coordinate where the line will be drawn
                        color: Colors.red,
                        strokeWidth: 2,
                        dashArray: [5, 5], // Optional: makes the line dashed
                        label: VerticalLineLabel(
                          show: true,
                          labelResolver:
                              (line) =>
                                  '${spots[startIndex].x.toStringAsFixed(1)}km, ${spots[startIndex].y.toStringAsFixed(0)}m',
                        ),
                      ),
                      VerticalLine(
                        x:
                            spots[endIndex]
                                .x, // X-axis coordinate where the line will be drawn
                        color: Colors.blue,
                        strokeWidth: 2,
                        dashArray: [5, 5], // Optional: makes the line dashed
                        label: VerticalLineLabel(
                          show: true,
                          labelResolver:
                              (line) =>
                                  '${spots[endIndex].x.toStringAsFixed(1)}km, ${spots[endIndex].y.toStringAsFixed(0)}m',
                        ),
                      ),
                    ],
                  ),
                  // Optionally add gradient background for better visualization
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(color: Colors.grey),
                  ),

                  // X-axis setup (Distance)
                  // bottomAxis: FlBottomAxisData(
                  //   show: true,
                  //   axisLine: AxisLine(strokeWidth: 1),
                  //   // Label every 0.5 km for readability
                  //   getTitlesWidget: (value, needSpacing) {
                  //     return Padding(
                  //       padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  //       child: Text(
                  //         '${value.toStringAsFixed(1)} km',
                  //         style: TextStyle(
                  //           fontSize: 12,
                  //           color: Colors.grey[600],
                  //         ),
                  //       ),
                  //     );
                  //   },
                  // ),
                  // X-axis setup (Distance)
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${value.toInt()}m',
                            style: const TextStyle(fontSize: 12),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              '${value.toStringAsFixed(1)} km',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                  // Grid lines and etc.
                  gridData: FlGridData(show: false),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Displaying some key metrics or the raw data structure for confirmation
            // Add text at bottom showing total altitude gain and loss between the two points
            Text(
              'Distance Between Points: ${calculateDistanceBasedOnGpx(trackPoints, currentPosition, endIndex).toStringAsFixed(1)}km',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Row(
              children: [
                Text(
                  'Altitude Change Between Points: ',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  'Gain: ${altitudeGain.toStringAsFixed(0)}m ',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Loss: ${altitudeLoss.toStringAsFixed(0)}m',
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Show total height gain and loss for the complete trail
            Text(
              'Total Trail Statistics:',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Row(
              children: [
                Text(
                  'Gain: ${altitudeGainTotal.toStringAsFixed(0)}m ',
                  style: TextStyle(
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Loss: ${altitudeLossTotal.toStringAsFixed(0)}m',
                  style: TextStyle(
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                if (graphData.isNotEmpty) ...[
                  Text(
                    'Total Distance: ${graphData.last.$1.toStringAsFixed(1)}km, ',
                  ),
                  Text(
                    'Max Altitude: ${graphData.fold<double>(0.0, (max, item) => item.$2 > max ? item.$2 : max).toStringAsFixed(0)} meters',
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Calculates the cumulative distance and altitude for each point in the track.
  List<(double distance, double altitude)> calculateAltitudeVsDistance(
    List<TrackPoint> points,
  ) {
    if (points.isEmpty) return [];

    final List<(double distance, double altitude)> graphData = [];
    double totalDistance = 0.0;

    for (int i = 0; i < points.length; i++) {
      double calculatedDistance = 0.0;

      if (i > 0) {
        // Calculate distance from the previous point to the current point
        calculatedDistance = totalDistanceBetween(points, i - 1, i);
        totalDistance += calculatedDistance;
      } else {
        // For the first point, we assume a starting distance of 0.
        totalDistance = 0.0;
      }

      graphData.add((totalDistance, points[i].elevation));
    }
    return graphData;
  }

  double _minAltitude(List<FlSpot> spots) =>
      spots.isEmpty ? 0 : spots.map((s) => s.y).reduce(min);

  double _maxAltitude(List<FlSpot> spots) =>
      spots.isEmpty ? 0 : spots.map((s) => s.y).reduce(max);
}
