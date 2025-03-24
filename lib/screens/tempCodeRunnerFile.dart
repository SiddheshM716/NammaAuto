import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:location/location.dart';
import '../services/supabase_service.dart';
import 'package:url_launcher/url_launcher.dart';

class NavigationScreen extends StatefulWidget {
  final LatLng pickupLocation;
  final LatLng dropLocation;
  final LatLng driverLocation;
  final int requestId;

  const NavigationScreen({
    Key? key,
    required this.pickupLocation,
    required this.dropLocation,
    required this.driverLocation,
    required this.requestId,
  }) : super(key: key);

  @override
  _NavigationScreenState createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  GoogleMapController? _mapController;
  Set<Polyline> _polylines = {};
  Location _location = Location();
  LatLng? _currentLocation;
  String _distance = '';
  String _duration = '';
  bool _isPickedUp = false;
  final String _googleMapsApiKey = 'AIzaSyAvibCYQuoqU1BNqfWV0QkTXvT39-Wz954';
  final SupabaseService _supabaseService = SupabaseService();
  final TextEditingController _otpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _fetchRoute(widget.driverLocation, widget.pickupLocation);
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
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
        _currentLocation = LatLng(locationData.latitude!, locationData.longitude!);
        _updateMap();
      });
    });
  }

  void _updateMap() {
    if (_currentLocation == null || _mapController == null) return;

    _mapController!.animateCamera(CameraUpdate.newLatLng(_currentLocation!));
  }

  Future<void> _fetchRoute(LatLng origin, LatLng destination) async {
    final String url = 'https://routes.googleapis.com/directions/v2:computeRoutes';

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
        'X-Goog-FieldMask': 'routes.duration,routes.distanceMeters,routes.polyline',
      },
      body: json.encode(requestBody),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['routes'] != null && data['routes'].isNotEmpty) {
        final polyline = data['routes'][0]['polyline']['encodedPolyline'];
        final duration = data['routes'][0]['duration'] ?? '0s';
        final distance = data['routes'][0]['distanceMeters'] ?? 0;

        setState(() {
          _distance = '${(distance / 1000).toStringAsFixed(1)} km';
          _duration = _formatDuration(duration);
          _polylines.clear();
          _polylines.add(
            Polyline(
              polylineId: PolylineId('route'),
              points: _decodePolyline(polyline),
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

  String _formatDuration(String duration) {
    final seconds = int.tryParse(duration.replaceAll('s', '')) ?? 0;

    if (seconds < 60) {
      return '$seconds seconds';
    } else if (seconds < 3600) {
      final minutes = (seconds / 60).round();
      return '$minutes mins';
    } else {
      final hours = (seconds / 3600).floor();
      final minutes = ((seconds % 3600) / 60).round();
      return '$hours hour${hours > 1 ? 's' : ''} $minutes mins';
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

  Future<void> _onPickupConfirmed() async {
    // Show OTP input dialog
    final enteredOTP = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Enter OTP'),
          content: TextField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(hintText: 'Enter OTP'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, _otpController.text),
              child: Text('Submit'),
            ),
          ],
        );
      },
    );

    if (enteredOTP == null || enteredOTP.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter the OTP')),
      );
      return;
    }

    // Fetch OTP from the database
    final rideRequest = await _supabaseService.fetchRideRequestById(widget.requestId);
    final storedOTP = rideRequest['otp'];

    if (enteredOTP == storedOTP) {
      setState(() {
        _isPickedUp = true;
      });

      // Fetch route to drop location
      _fetchRoute(_currentLocation!, widget.dropLocation);

      // Calculate bounds to fit both pickup and drop locations
      final bounds = LatLngBounds(
        southwest: LatLng(
          widget.pickupLocation.latitude < widget.dropLocation.latitude
              ? widget.pickupLocation.latitude
              : widget.dropLocation.latitude,
          widget.pickupLocation.longitude < widget.dropLocation.longitude
              ? widget.pickupLocation.longitude
              : widget.dropLocation.longitude,
        ),
        northeast: LatLng(
          widget.pickupLocation.latitude > widget.dropLocation.latitude
              ? widget.pickupLocation.latitude
              : widget.dropLocation.latitude,
          widget.pickupLocation.longitude > widget.dropLocation.longitude
              ? widget.pickupLocation.longitude
              : widget.dropLocation.longitude,
        ),
      );

      // Animate camera to fit the bounds
      if (_mapController != null) {
        final double screenHeight = MediaQuery.of(context).size.height;
        final double screenWidth = MediaQuery.of(context).size.width;
        final double maxPadding = (screenHeight / 2).clamp(0, screenWidth / 2);
        final double padding = maxPadding * 0.4;

        _mapController!.animateCamera(
          CameraUpdate.newLatLngBounds(bounds, padding),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invalid OTP. Please try again.')),
      );
    }
  }

  Future<void> _launchGoogleMapsNavigation(LatLng destination) async {
    final String url = 'https://www.google.com/maps/dir/?api=1&destination=${destination.latitude},${destination.longitude}&travelmode=driving';

    if (await canLaunch(url)) {
      await launch(url);
    } else {
      throw 'Could not launch $url';
    }
  }

  Future<void> _onEndRide() async {
    // Update ride status to completed
    await _supabaseService.updateRideStatus(
      requestId: widget.requestId,
      reqStatus: true,
    );

    // Navigate back to the DriverScreen
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) {
              _mapController = controller;
            },
            initialCameraPosition: CameraPosition(
              target: widget.driverLocation,
              zoom: 14,
            ),
            markers: {
              if (_currentLocation != null)
                Marker(
                  markerId: MarkerId('currentLocation'),
                  position: _currentLocation!,
                  infoWindow: InfoWindow(title: 'Your Location'),
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
                ),
              Marker(
                markerId: MarkerId('pickup'),
                position: widget.pickupLocation,
                infoWindow: InfoWindow(title: 'Pickup Location'),
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
              ),
              if (_isPickedUp)
                Marker(
                  markerId: MarkerId('drop'),
                  position: widget.dropLocation,
                  infoWindow: InfoWindow(title: 'Drop Location'),
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                ),
            },
            polylines: _polylines,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
          ),
          Positioned(
            top: 16,
            left: 16,
            child: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Distance: $_distance'),
                  Text('Duration: $_duration'),
                ],
              ),
            ),
          ),
          if (!_isPickedUp)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Column(
                children: [
                  ElevatedButton(
                    onPressed: _onPickupConfirmed,
                    child: Text('Enter OTP'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => _launchGoogleMapsNavigation(widget.pickupLocation),
                    child: Text('Navigate to Pickup'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ],
              ),
            ),
          if (_isPickedUp)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: Column(
                children: [
                  ElevatedButton(
                    onPressed: _onEndRide,
                    child: Text('End Ride'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => _launchGoogleMapsNavigation(widget.dropLocation),
                    child: Text('Navigate to Drop'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}