import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class RealTimeMap extends StatefulWidget {
  const RealTimeMap({super.key});

  @override
  _RealTimeMapState createState() => _RealTimeMapState();
}

class _RealTimeMapState extends State<RealTimeMap> {
  GoogleMapController? _controller;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  Timer? _timer;
  BitmapDescriptor? _customIcon;

  @override
  void initState() {
    super.initState();
    _loadCustomMarker();
    _fetchDrivers();
    _timer = Timer.periodic(Duration(seconds: 3), (timer) => _fetchDrivers()); // Update every 3 seconds
  }

  // Load custom marker
  Future<void> _loadCustomMarker() async {
    _customIcon = await BitmapDescriptor.fromAssetImage(
      const ImageConfiguration(size: Size(48, 48)),
      'assets/auto.png', // Path to your custom marker image
    );
  }

  // Fetch driver data from API
  Future<void> _fetchDrivers() async {
    try {
      final response = await http.get(Uri.parse("http://10.9.115.135:8001/drivers"));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List drivers = data["drivers"];

        if (drivers.isEmpty) {
          print("No drivers available");
          return;
        }

        print("Updated driver data: $drivers");

        Set<Marker> newMarkers = {};
        Set<Polyline> newPolylines = {};

        for (var driver in drivers) {
          // Create a new marker
          Marker newMarker = Marker(
            markerId: MarkerId(driver["id"].toString()), // Use driver ID as the marker ID
            position: LatLng(driver["latitude"], driver["longitude"]), // Latitude and Longitude
            infoWindow: InfoWindow(title: "Driver ${driver["id"]}"),
            icon: _customIcon ?? BitmapDescriptor.defaultMarker,
          );
          newMarkers.add(newMarker);

          // Fetch and draw the route polyline for the driver
          await _fetchRoutePolyline(driver["id"], newPolylines);
        }

        setState(() {
          _markers = newMarkers;
          _polylines = newPolylines;
        });
      }
    } catch (e) {
      print("Error fetching driver locations: $e");
    }
  }

  // Fetch and draw the route polyline for a driver
  Future<void> _fetchRoutePolyline(int driverId, Set<Polyline> newPolylines) async {
    try {
      final response = await http.get(Uri.parse("http://10.9.115.135:8001/route/$driverId"));
      if (response.statusCode == 200) {
        final routeData = jsonDecode(response.body);
        String encodedPolyline = routeData["polyline"];
        List<LatLng> points = _decodePolyline(encodedPolyline);

        newPolylines.add(Polyline(
          polylineId: PolylineId("route_$driverId"),
          points: points,
          color: Colors.blue,
          width: 5,
        ));
      }
    } catch (e) {
      print("Error fetching route polyline for driver $driverId: $e");
    }
  }

  // Decode Google Maps polyline
  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: LatLng(12.9716, 77.5946), // Initial camera position (Bengaluru)
          zoom: 12,
        ),
        markers: _markers,
        polylines: _polylines,
        onMapCreated: (GoogleMapController controller) {
          _controller = controller;
        },
      ),
    );
  }
}