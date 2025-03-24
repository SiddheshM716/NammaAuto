

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: RoadMapScreen(),
    );
  }
}

class RoadMapScreen extends StatefulWidget {
  const RoadMapScreen({super.key});

  @override
  _RoadMapScreenState createState() => _RoadMapScreenState();
}

class _RoadMapScreenState extends State<RoadMapScreen> {
  GoogleMapController? mapController;
  Set<Polyline> polylines = {};
  TextEditingController latController = TextEditingController(text: "13.089331");
  TextEditingController lonController = TextEditingController(text: "77.547581");
  LatLng? currentLocation;
  Marker? autoMarker;
  BitmapDescriptor? autoIcon;

  @override
  void initState() {
    super.initState();
    _loadAutoMarkerIcon();
    _requestLocationPermissionAndFetchLocation();
  }

  Future<void> _loadAutoMarkerIcon() async {
    final ImageConfiguration imageConfiguration = ImageConfiguration(size: Size(50, 50));
    BitmapDescriptor icon = await BitmapDescriptor.fromAssetImage(
      imageConfiguration,
      'assets/auto.png',
    );
    setState(() {
      autoIcon = icon;
    });
  }

  Future<void> _requestLocationPermissionAndFetchLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Location services are disabled. Please enable them.")),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Location permissions are denied.")),
        );
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Location permissions are permanently denied. Enable them in settings.")),
      );
      return;
    }

    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    setState(() {
      currentLocation = LatLng(position.latitude, position.longitude);
    });

    mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(currentLocation!, 14),
    );
  }

  Future<void> fetchRoadsFromAPI() async {
    String lat = latController.text;
    String lon = lonController.text;
    String apiUrl = "http://192.168.1.40:8001/roaming-area?lat=$lat&lon=$lon";

    try {
      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode == 200) {
        Map<String, dynamic> data = json.decode(response.body);
        List<dynamic> roadsData = data['road_network']['roads'];
        Set<Polyline> roadPolylines = {};
        List<LatLng> allRoadPoints = [];

        for (int i = 0; i < roadsData.length; i++) {
          List<LatLng> roadPoints = roadsData[i]
              .map<LatLng>((coord) => LatLng(coord[1], coord[0])) // Convert [lon, lat] to LatLng
              .toList();
          allRoadPoints.addAll(roadPoints);

          roadPolylines.add(
            Polyline(
              polylineId: PolylineId("road_$i"),
              color: Colors.red,
              width: 4,
              points: roadPoints,
            ),
          );
        }

        // **Find nearest road point to autoLocation**
        LatLng enteredLocation = LatLng(double.parse(lat), double.parse(lon));
        LatLng? nearestRoadPoint = _findNearestPoint(enteredLocation, allRoadPoints);

        // **Fetch actual route using Google Routes API**
        print("Nearest Road Point: ${nearestRoadPoint.latitude}, ${nearestRoadPoint.longitude}");

        List<LatLng> routePoints = await _getRouteFromGoogleRoutesAPI(enteredLocation, nearestRoadPoint);
        print("Route Points Count: ${routePoints.length}");
        if (routePoints.isNotEmpty) {
          roadPolylines.add(
            Polyline(
              polylineId: PolylineId("auto_to_road"),
              color: Colors.blue,
              width: 5,
              points: routePoints, // Use fetched route
            ),
          );
          
        }
        else {
          print("Error: No route points received from Google Routes API!");
        }
      
        setState(() {
          polylines = roadPolylines;
          autoMarker = Marker(
            markerId: MarkerId("auto_marker"),
            position: enteredLocation,
            infoWindow: InfoWindow(title: "Auto Available"),
            icon: autoIcon ?? BitmapDescriptor.defaultMarker,
          );
        });

        _adjustCameraView(allRoadPoints, enteredLocation);
      } else {
        print("Failed to load roads: ${response.statusCode}");
      }
    } catch (e) {
      print("Error fetching roads: $e");
    }
  }



  void _adjustCameraView(List<LatLng> roadPoints, LatLng? autoLocation) {
    if (mapController == null || roadPoints.isEmpty) return;

    double minLat = roadPoints.first.latitude, maxLat = roadPoints.first.latitude;
    double minLon = roadPoints.first.longitude, maxLon = roadPoints.first.longitude;

    for (var point in roadPoints) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLon) minLon = point.longitude;
      if (point.longitude > maxLon) maxLon = point.longitude;
    }

    if (autoLocation != null) {
      minLat = min(minLat, autoLocation.latitude);
      maxLat = max(maxLat, autoLocation.latitude);
      minLon = min(minLon, autoLocation.longitude);
      maxLon = max(maxLon, autoLocation.longitude);
    }

    LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(minLat, minLon),
      northeast: LatLng(maxLat, maxLon),
    );

    mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Roads from API")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: latController,
                    decoration: InputDecoration(labelText: "Latitude"),
                    keyboardType: TextInputType.number,
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: lonController,
                    decoration: InputDecoration(labelText: "Longitude"),
                    keyboardType: TextInputType.number,
                  ),
                ),
                SizedBox(width: 10),
                ElevatedButton(
                  onPressed: fetchRoadsFromAPI,
                  child: Text("Fetch Roads"),
                ),
              ],
            ),
          ),
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: currentLocation ?? LatLng(13.089331, 77.547581),
                zoom: 14,
              ),
              style: _darkMapStyle, // Apply the map style here
              onMapCreated: (GoogleMapController controller) {
                mapController = controller;
              },
              polylines: polylines,
              markers: autoMarker != null ? {autoMarker!} : {},
            ),
          ),
        ],
      ),
    );
  }
}
const String _darkMapStyle = '''
[
  {
    "featureType": "all",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#242f3e"
      }
    ]
  },
  {
    "featureType": "all",
    "elementType": "labels.text.stroke",
    "stylers": [
      {
        "lightness": -80
      }
    ]
  },
  {
    "featureType": "administrative",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#746855"
      }
    ]
  },
  {
    "featureType": "administrative.locality",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#d59563"
      }
    ]
  },
  {
    "featureType": "poi",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#d59563"
      }
    ]
  },
  {
    "featureType": "poi.park",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#263c3f"
      }
    ]
  },
  {
    "featureType": "poi.park",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#6b9a76"
      }
    ]
  },
  {
    "featureType": "road",
    "elementType": "geometry.fill",
    "stylers": [
      {
        "color": "#2b3544"
      }
    ]
  },
  {
    "featureType": "road",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#9ca5b3"
      }
    ]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry.fill",
    "stylers": [
      {
        "color": "#746855"
      }
    ]
  },
  {
    "featureType": "road.highway",
    "elementType": "geometry.stroke",
    "stylers": [
      {
        "color": "#1f2835"
      }
    ]
  },
  {
    "featureType": "road.highway",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#f3d19c"
      }
    ]
  },
  {
    "featureType": "transit",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#2f3948"
      }
    ]
  },
  {
    "featureType": "transit.station",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#d59563"
      }
    ]
  },
  {
    "featureType": "water",
    "elementType": "geometry",
    "stylers": [
      {
        "color": "#17263c"
      }
    ]
  },
  {
    "featureType": "water",
    "elementType": "labels.text.fill",
    "stylers": [
      {
        "color": "#515c6d"
      }
    ]
  },
  {
    "featureType": "water",
    "elementType": "labels.text.stroke",
    "stylers": [
      {
        "lightness": -20
      }
    ]
  }
]
''';
LatLng _findNearestPoint(LatLng autoLocation, List<LatLng> roadPoints) {
  LatLng nearestPoint = roadPoints.first;
  double minDistance = _calculateDistance(autoLocation, roadPoints.first);

  for (LatLng point in roadPoints) {
    double distance = _calculateDistance(autoLocation, point);
    if (distance < minDistance) {
      minDistance = distance;
      nearestPoint = point;
    }
  }
  return nearestPoint;
}

double _calculateDistance(LatLng point1, LatLng point2) {
  const double R = 6371e3; // Earth radius in meters
  double lat1 = point1.latitude * pi / 180;
  double lat2 = point2.latitude * pi / 180;
  double deltaLat = (point2.latitude - point1.latitude) * pi / 180;
  double deltaLon = (point2.longitude - point1.longitude) * pi / 180;

  double a = sin(deltaLat / 2) * sin(deltaLat / 2) +
      cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2);
  double c = 2 * atan2(sqrt(a), sqrt(1 - a));

  return R * c; // Returns distance in meters
}

Future<List<LatLng>> _getRouteFromGoogleRoutesAPI(LatLng start, LatLng end) async {
  const String googleApiKey = "AIzaSyAvibCYQuoqU1BNqfWV0QkTXvT39-Wz954"; // Replace with your actual API key
  final String apiUrl = "https://routes.googleapis.com/directions/v2:computeRoutes";

  // Debug: Print the start and end points
  print("Start Point: ${start.latitude}, ${start.longitude}");
  print("End Point: ${end.latitude}, ${end.longitude}");

  // Define the request body
  final Map<String, dynamic> requestBody = {
    "origin": {
      "location": {
        "latLng": {"latitude": start.latitude, "longitude": start.longitude}
      }
    },
    "destination": {
      "location": {
        "latLng": {"latitude": end.latitude, "longitude": end.longitude}
      }
    },
    "travelMode": "DRIVE",
    "routingPreference": "TRAFFIC_AWARE",
    "computeAlternativeRoutes": false,
    "polylineEncoding": "ENCODED_POLYLINE",
  };

  // Debug: Print the request body
  print("Request Body: ${json.encode(requestBody)}");

  try {
    // Make the API request
    final response = await http.post(
      Uri.parse(apiUrl),
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": googleApiKey,
        "X-Goog-FieldMask": "routes.polyline.encodedPolyline"
      },
      body: json.encode(requestBody),
    );

    // Debug: Print the API response status code and body
    print("API Response Status Code: ${response.statusCode}");
    print("API Response Body: ${response.body}");

    if (response.statusCode == 200) {
      // Parse the response
      Map<String, dynamic> data = json.decode(response.body);
      List<LatLng> routePoints = [];

      if (data["routes"] != null && data["routes"].isNotEmpty) {
        // Extract the encoded polyline
        String encodedPolyline = data["routes"][0]["polyline"]["encodedPolyline"];
        print("Encoded Polyline: $encodedPolyline");

        // Decode the polyline into a list of LatLng points
        routePoints = _decodePolyline(encodedPolyline);

        // Debug: Print the decoded polyline points
        print("Decoded Polyline Points: $routePoints");
      } else {
        print("Error: No routes found in the API response.");
      }

      return routePoints;
    } else {
      // Handle API errors
      print("Failed to fetch route: ${response.statusCode} - ${response.body}");
      return [];
    }
  } catch (e) {
    // Handle exceptions
    print("Error in _getRouteFromGoogleRoutesAPI: $e");
    return [];
  }
}
List<LatLng> _decodePolyline(String encoded) {
  List<LatLng> points = [];
  int index = 0, len = encoded.length;
  int lat = 0, lng = 0;

  while (index < len) {
    // Decode latitude
    int shift = 0, result = 0;
    int b;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1F) << shift;
      shift += 5;
    } while (b >= 0x20);
    int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
    lat += dlat;

    // Decode longitude
    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1F) << shift;
      shift += 5;
    } while (b >= 0x20);
    int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
    lng += dlng;

    // Add the decoded point to the list
    points.add(LatLng(lat / 1E5, lng / 1E5));
  }

  // Debug: Print decoded points
  print("Decoded Polyline Points: $points");
  return points;
}