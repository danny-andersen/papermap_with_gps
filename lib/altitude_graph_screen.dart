import 'package:flutter/material.dart';
import 'dart:math';
// Import the charting library
import 'package:fl_chart/fl_chart.dart';
// Assuming TrackPoint definition is available, perhaps in lib/common.dart or a model file
import 'package:papermap_with_gps/common.dart'; // Replace with actual module name where CommonUtils resides

class AltitudeGraphScreen extends StatelessWidget {
  final List<TrackPoint> trackPoints;

  const AltitudeGraphScreen({Key? key, required this.trackPoints})
    : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 1. Process the data to get (Distance, Altitude) pairs
    final List<(double distance, double altitude)> graphData =
        calculateAltitudeVsDistance(trackPoints);
    final spots =
        graphData
            .map((item) => FlSpot(item.$1.toDouble(), item.$2.toDouble()))
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Altitude vs Distance Traveled'),
        backgroundColor: Colors.blueGrey,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Altitude vs Distance',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 20),
            // Replaced the placeholder Container with fl_chart LineChartWidget
            SizedBox(
              height: 300,
              child: LineChart(
                LineChartData(
                  minX: 0,
                  minY: _minAltitude(spots),
                  maxY: _maxAltitude(spots),
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
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                      ),
                    ),
                  ),
                  // // Y-axis setup (Altitude)
                  // leftTitles: SideTitles(
                  //   showTitles: true,
                  //   interval: 50.0, // Show labels every 50 meters
                  //   getTitlesWidget: (value, meta) {
                  //     return Text('${value.toInt()}m');
                  //   },
                  //   reservedSize: 40, // Reserve space for the Y-axis label text
                  // ),

                  // Grid lines and etc.
                  gridData: FlGridData(show: true),
                ),
              ),
            ),
            const SizedBox(height: 30),
            // Displaying some key metrics or the raw data structure for confirmation
            if (graphData.isNotEmpty) ...[
              Text(
                'Total Distance Traveled: ${graphData.last.$1.toStringAsFixed(2)} km',
              ),
              Text(
                'Maximum Altitude Reached: ${graphData.fold<double>(0.0, (max, item) => item.$2 > max ? item.$2 : max).toStringAsFixed(2)} meters',
              ),
            ],
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
