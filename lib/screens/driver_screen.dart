import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/supabase_service.dart';
import '../services/google_maps_service.dart';
import '../utils/notification_utils.dart';
import 'dart:async';
import 'package:location/location.dart';
import 'navigation_screen.dart';
import 'heatmap.dart';
import 'home_screen.dart';

class DriverScreen extends StatefulWidget {
  @override
  _DriverScreenState createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  final GoogleMapsService _googleMapsService = GoogleMapsService();
  List<Map<String, dynamic>> rideRequests = [];
  Timer? _timer;
  bool _isLoading = true;
  GoogleMapController? _mapController;
  Location _location = Location();
  LatLng? _driverLocation;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {}; // For drawing the route
  int _timerSeconds = 20;
  Timer? _countdownTimer;
  final String _googleMapsApiKey = 'AIzaSyAvibCYQuoqU1BNqfWV0QkTXvT39-Wz954'; // Replace with your API key

  @override
  void initState() {
    super.initState();
    NotificationUtils.init();
    _fetchRideRequests();

    // Fetch ride requests every 20 seconds
    _timer = Timer.periodic(Duration(seconds: 20), (timer) {
      _fetchRideRequests();
    });

    _getDriverLocation();
    _startCountdownTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _countdownTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _startCountdownTimer() {
  _countdownTimer?.cancel();
  _timerSeconds = 20;
  _countdownTimer = Timer.periodic(Duration(seconds: 1), (timer) async {
    if (_timerSeconds > 0) {
      if (mounted) {
        setState(() {
          _timerSeconds--;
        });
      }
    } else {
      _countdownTimer?.cancel();
      if (rideRequests.isNotEmpty) {
        await _cancelRideRequest();
      }
      await _fetchRideRequests();
      if (rideRequests.isNotEmpty && mounted) {
        _startCountdownTimer();
      }
    }
  });
}

  Future<void> _getDriverLocation() async {
    bool serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) return;
    }

    PermissionStatus permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) return;
    }

    _location.onLocationChanged.listen((LocationData locationData) {
  if (!mounted || locationData.latitude == null || locationData.longitude == null) return;

  setState(() {
    _driverLocation = LatLng(locationData.latitude!, locationData.longitude!);
    _updateMap();
    _updateMarkers();
  });
});
  }

  void _updateMap() {
    if (_driverLocation == null || _mapController == null) return;
    _mapController!.animateCamera(CameraUpdate.newLatLng(_driverLocation!));
  }

  Future<void> _fetchRideRequests() async {
  if (!mounted) return;

  setState(() {
    _isLoading = true;
  });

  try {
    final requests = await _supabaseService.fetchRideRequests();
    final validRequests = requests.where((request) =>
        request['ride_cancelled'] != true && request['ride_accepted'] != true).toList();

    await Future.wait(validRequests.map((request) async {
      try {
        Map<String, String> categoryData = await _googleMapsService.getLocationCategoryAndTier(request['drop_address']);
        request['place_type'] = categoryData['category'];
        request['priority'] = categoryData['tier'];
      } catch (e) {
        request['place_type'] = 'Unknown';
        request['priority'] = 'Tier 4';
      }
    }));

    validRequests.sort((a, b) => _comparePriority(a['priority'], b['priority']));

    if (mounted) {
      setState(() {
        rideRequests = validRequests;
        _isLoading = false;
      });

      if (rideRequests.isNotEmpty) {
        _startCountdownTimer();
      }
    }

    _showNotifications();
    _updateMarkers();
  } catch (e) {
    if (mounted) {
      setState(() {
        rideRequests = [];
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch ride requests: $e')),
      );
    }
  }
}

  void _updateMarkers() {
  if (!mounted) return;

  setState(() {
    _markers.clear();
    _polylines.clear();

    if (rideRequests.isNotEmpty) {
      final request = rideRequests.first;

      if (request['pick_up_lat'] == null || request['pick_up_lng'] == null ||
          request['drop_lat'] == null || request['drop_lng'] == null) {
        print('Invalid LatLng values in ride request');
        return;
      }

      final LatLng pickupLocation = LatLng(
        request['pick_up_lat'],
        request['pick_up_lng'],
      );
      final LatLng dropLocation = LatLng(
        request['drop_lat'],
        request['drop_lng'],
      );

      _markers.add(
        Marker(
          markerId: MarkerId('pickup'),
          position: pickupLocation,
          infoWindow: InfoWindow(title: 'Pickup', snippet: request['pick_up_address']),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      );
      _markers.add(
        Marker(
          markerId: MarkerId('drop'),
          position: dropLocation,
          infoWindow: InfoWindow(title: 'Drop', snippet: request['drop_address']),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );

      _fetchRoute(pickupLocation, dropLocation);

      final bounds = LatLngBounds(
        southwest: LatLng(
          pickupLocation.latitude < dropLocation.latitude
              ? pickupLocation.latitude
              : dropLocation.latitude,
          pickupLocation.longitude < dropLocation.longitude
              ? pickupLocation.longitude
              : dropLocation.longitude,
        ),
        northeast: LatLng(
          pickupLocation.latitude > dropLocation.latitude
              ? pickupLocation.latitude
              : dropLocation.latitude,
          pickupLocation.longitude > dropLocation.longitude
              ? pickupLocation.longitude
              : dropLocation.longitude,
        ),
      );

      if (_mapController != null) {
        final double screenHeight = MediaQuery.of(context).size.height;
        final double screenWidth = MediaQuery.of(context).size.width;
        final double maxPadding = (screenHeight / 2).clamp(0, screenWidth / 2);
        final double padding = maxPadding * 0.4;

        _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, padding),
        );
      }
    }
  });
}

  Future<void> _fetchRoute(LatLng origin, LatLng destination) async {
    final String url =
        'https://routes.googleapis.com/directions/v2:computeRoutes';

    final Map<String, dynamic> requestBody = {
      "origin": {
        "location": {
          "latLng": {
            "latitude": origin.latitude,
            "longitude": origin.longitude,
          }
        }
      },
      "destination": {
        "location": {
          "latLng": {
            "latitude": destination.latitude,
            "longitude": destination.longitude,
          }
        }
      },
      "travelMode": "DRIVE",
    };

    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': _googleMapsApiKey,
        'X-Goog-FieldMask': 'routes.polyline',
      },
      body: json.encode(requestBody),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['routes'] != null && data['routes'].isNotEmpty) {
        final polyline = data['routes'][0]['polyline']['encodedPolyline'];
        final List<LatLng> routeCoordinates = _decodePolyline(polyline);

        setState(() {
          _polylines.clear();
          _polylines.add(
            Polyline(
              polylineId: PolylineId('route'),
              points: routeCoordinates,
              color: Colors.blue,
              width: 5,
            ),
          );
        });
      }
    } else {
      print('Failed to fetch route: ${response.statusCode}');
      print('Response: ${response.body}');
    }
  }

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

  int _comparePriority(String priorityA, String priorityB) {
    List<String> priorityOrder = ['Tier 1', 'Tier 2', 'Tier 3', 'Tier 4'];
    return priorityOrder.indexOf(priorityA).compareTo(priorityOrder.indexOf(priorityB));
  }

  void _showNotifications() async {
    if (rideRequests.isNotEmpty) {
      final request = rideRequests.first;
      await NotificationUtils.showNotification(
        title: 'New Ride Request',
        body: 'Pickup: ${request['pick_up_address']}, Drop: ${request['drop_address']}',
      );
    }
  }

  Future<void> _cancelRideRequest() async {
    if (rideRequests.isNotEmpty) {
      final request = rideRequests.first;
      await _supabaseService.insertRideStatus(
        driverId: 1, // Replace with actual driver ID
        requestId: request['id'],
        rideCancelled: true,
      );

      if (mounted) {
        setState(() {
          rideRequests.removeAt(0);
        });
      }
    }
  }

  Future<void> _acceptRideRequest() async {
    if (rideRequests.isNotEmpty) {
      final request = rideRequests.first;
      await _supabaseService.insertRideStatus(
        driverId: 1, // Replace with actual driver ID
        requestId: request['id'],
        rideAccepted: true,
      );

      if (_driverLocation != null) {
        final LatLng pickupLocation = LatLng(
          request['pick_up_lat'],
          request['pick_up_lng'],
        );
        final LatLng dropLocation = LatLng(
          request['drop_lat'],
          request['drop_lng'],
        );

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NavigationScreen(
              pickupLocation: pickupLocation,
              dropLocation: dropLocation,
              driverLocation: _driverLocation!,
              requestId: request['id'],
            ),
          ),
        );
      }

      if (mounted) {
        setState(() {
          rideRequests.removeAt(0);
        });
      }
    }
  }

  Widget _buildBackButton() {
    return Positioned(
      top: 16,
      left: 16,
      child: FloatingActionButton(
        mini: true,
        onPressed: () {
          Navigator.pop(context);
        },
        child: Icon(Icons.arrow_back, color: Colors.white),
        backgroundColor: Colors.blue,
      ),
    );
  }

  Widget _buildRideRequestCard() {
    if (rideRequests.isEmpty) return SizedBox.shrink();

    final request = rideRequests.first;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: Offset(0, -2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: _timerSeconds / 20,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
            SizedBox(height: 16),
            Text('Ride Request', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('Pickup: ${request['pick_up_address']}', style: TextStyle(fontSize: 16)),
            Text('Drop: ${request['drop_address']}', style: TextStyle(fontSize: 16)),
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.star, color: Colors.amber, size: 16),
                SizedBox(width: 4),
                Text('Priority: ${request['priority']}', style: TextStyle(fontSize: 14)),
              ],
            ),
            SizedBox(height: 8),
            Text('Place Type: ${request['place_type']}', style: TextStyle(fontSize: 14)),
            SizedBox(height: 16),
            Text('Time remaining: $_timerSeconds seconds', style: TextStyle(fontSize: 14, color: Colors.grey)),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton.icon(
                  onPressed: _cancelRideRequest,
                  icon: Icon(Icons.cancel, color: Colors.white),
                  label: Text('Cancel'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _acceptRideRequest,
                  icon: Icon(Icons.check, color: Colors.white),
                  label: Text('Accept'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
Widget build(BuildContext context) {
  return Scaffold(
    body: Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          bottom: rideRequests.isNotEmpty ? MediaQuery.of(context).size.height * 0.5 : 0,
          child: GoogleMap(
            onMapCreated: (controller) {
              _mapController = controller;
              _updateMap();
            },
            initialCameraPosition: CameraPosition(
              target: _driverLocation ?? LatLng(12.9716, 77.5946),
              zoom: 14,
            ),
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
          ),
        ),
        _buildBackButton(),
        if (rideRequests.isNotEmpty) _buildRideRequestCard(),

        // Floating Action Button to Navigate to RealTimeMap (Bottom Left)
        Positioned(
          left: 16,
          bottom: 16,
          child: FloatingActionButton(
            heroTag: "realTimeMapButton",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => RoadMapScreen()),
              );
            },
            child: Icon(Icons.map),
            backgroundColor: Colors.blue,
          ),
        ),

        // Floating Action Button to Navigate to HomeScreen (Menu Button - Top Right)
        Positioned(
          top: 40, // Adjust as needed for spacing
          right: 16,
          child: FloatingActionButton(
            heroTag: "menuButton",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => HomeScreen()),
              );
            },
            child: Icon(Icons.menu),
            backgroundColor: Colors.green,
            mini: true, // Optional: makes the button smaller
          ),
        ),
      ],
    ),
  );
}
}