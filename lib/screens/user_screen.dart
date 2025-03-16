import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/supabase_service.dart';
import 'package:location/location.dart';

class UserScreen extends StatefulWidget {
  @override
  _UserScreenState createState() => _UserScreenState();
}

class _UserScreenState extends State<UserScreen> {
  final SupabaseService _supabaseService = SupabaseService();
  GoogleMapController? _mapController;
  LatLng? _pickupLocation;
  LatLng? _dropLocation;
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropController = TextEditingController();
  final String _apiKey = "AIzaSyAvibCYQuoqU1BNqfWV0QkTXvT39-Wz954"; // Replace with your API key
  List<String> _pickupSuggestions = [];
  List<String> _dropSuggestions = [];
  Location _location = Location();
  bool _serviceEnabled = false;
  PermissionStatus _permissionGranted = PermissionStatus.denied;
  Set<Marker> _markers = {}; // Markers for pickup and drop locations
  Set<Polyline> _polylines = {}; // Polylines for the route

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  /// Fetches place suggestions as the user types
  Future<void> _fetchSuggestions(String query, {required bool isPickup}) async {
    final url =
        "https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$query&key=$_apiKey&components=country:in";

    final response = await http.get(Uri.parse(url));
    final data = jsonDecode(response.body);

    if (data["status"] == "OK") {
      setState(() {
        if (isPickup) {
          _pickupSuggestions = List<String>.from(
              data["predictions"].map((prediction) => prediction["description"]));
        } else {
          _dropSuggestions = List<String>.from(
              data["predictions"].map((prediction) => prediction["description"]));
        }
      });
    }
  }

  /// Converts an address into latitude and longitude using Google Geocoding API
  Future<void> _searchLocation(String place, {required bool isPickup}) async {
    final url =
        "https://maps.googleapis.com/maps/api/geocode/json?address=$place&key=$_apiKey";

    final response = await http.get(Uri.parse(url));
    final data = jsonDecode(response.body);

    if (data["status"] == "OK" && data["results"].isNotEmpty) {
      final location = data["results"][0]["geometry"]["location"];
      LatLng latLng = LatLng(location["lat"], location["lng"]);

      // Set the location and update the UI
      setState(() {
        if (isPickup) {
          _pickupLocation = latLng;
          _pickupController.text = place;
          _pickupSuggestions.clear();
        } else {
          _dropLocation = latLng;
          _dropController.text = place;
          _dropSuggestions.clear();
        }
      });

      // Move the camera to the selected location
      _mapController?.animateCamera(CameraUpdate.newLatLng(latLng));

      // Update markers and fetch route if both locations are selected
      _updateMarkers();
      if (_pickupLocation != null && _dropLocation != null) {
        _fetchRoute(_pickupLocation!, _dropLocation!);
        _zoomToFitMarkers(); // Zoom to fit all markers
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Location not found. Try again.")),
      );
    }
  }

  /// Fetches the route between pickup and drop locations using the Routes API
  Future<void> _fetchRoute(LatLng pickup, LatLng drop) async {
    final url = "https://routes.googleapis.com/directions/v2:computeRoutes";

    final Map<String, dynamic> requestBody = {
      "origin": {
        "location": {
          "latLng": {
            "latitude": pickup.latitude,
            "longitude": pickup.longitude,
          }
        }
      },
      "destination": {
        "location": {
          "latLng": {
            "latitude": drop.latitude,
            "longitude": drop.longitude,
          }
        }
      },
      "travelMode": "DRIVE",
    };

    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': _apiKey,
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

  /// Decodes the polyline string into a list of LatLng points
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

  /// Updates the markers on the map
  void _updateMarkers() {
    setState(() {
      _markers.clear();
      if (_pickupLocation != null) {
        _markers.add(
          Marker(
            markerId: MarkerId('pickup'),
            position: _pickupLocation!,
            infoWindow: InfoWindow(title: 'Pickup Location'),
          ),
        );
      }
      if (_dropLocation != null) {
        _markers.add(
          Marker(
            markerId: MarkerId('drop'),
            position: _dropLocation!,
            infoWindow: InfoWindow(title: 'Drop Location'),
          ),
        );
      }
    });
  }

  /// Zooms the map to fit all markers on the screen
  void _zoomToFitMarkers() {
  if (_pickupLocation == null || _dropLocation == null || _mapController == null) {
    return;
  }

  // Create a LatLngBounds object to fit both markers
  LatLngBounds bounds = LatLngBounds(
    southwest: LatLng(
      _pickupLocation!.latitude < _dropLocation!.latitude
          ? _pickupLocation!.latitude
          : _dropLocation!.latitude,
      _pickupLocation!.longitude < _dropLocation!.longitude
          ? _pickupLocation!.longitude
          : _dropLocation!.longitude,
    ),
    northeast: LatLng(
      _pickupLocation!.latitude > _dropLocation!.latitude
          ? _pickupLocation!.latitude
          : _dropLocation!.latitude,
      _pickupLocation!.longitude > _dropLocation!.longitude
          ? _pickupLocation!.longitude
          : _dropLocation!.longitude,
    ),
  );

  // Calculate padding based on screen size
  final double screenWidth = MediaQuery.of(context).size.width;
  final double screenHeight = MediaQuery.of(context).size.height;

  // Adjust padding to account for UI elements (e.g., text boxes, buttons)
  final double padding = screenHeight * 0.2; // 20% of screen height as padding

  // Animate the camera to fit the bounds with padding
  _mapController!.animateCamera(
    CameraUpdate.newLatLngBounds(bounds, padding),
  );
}

  /// Submits the ride request to Supabase
  Future<void> _submitRideRequest() async {
    if (_pickupLocation == null || _dropLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select both pickup and drop locations')),
      );
      return;
    }

    try {
      await _supabaseService.insertRideRequest(
        userId: 3,
        userName: 'John Doe',
        userPhno: '1234567890',
        pickUpLat: _pickupLocation!.latitude,
        pickUpLng: _pickupLocation!.longitude,
        dropLat: _dropLocation!.latitude,
        dropLng: _dropLocation!.longitude,
        dropAddress: _dropController.text,
        pickupAddress: _pickupController.text,
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ride request submitted successfully!')),
      );

      // Clear the form after submission
      _pickupController.clear();
      _dropController.clear();
      setState(() {
        _pickupLocation = null;
        _dropLocation = null;
        _markers.clear();
        _polylines.clear();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit ride request: $e')),
      );
    }
  }

  /// Checks and requests location permissions
  Future<void> _checkLocationPermission() async {
    _serviceEnabled = await _location.serviceEnabled();
    if (!_serviceEnabled) {
      _serviceEnabled = await _location.requestService();
      if (!_serviceEnabled) {
        return;
      }
    }

    _permissionGranted = await _location.hasPermission();
    if (_permissionGranted == PermissionStatus.denied) {
      _permissionGranted = await _location.requestPermission();
      if (_permissionGranted != PermissionStatus.granted) {
        return;
      }
    }
  }

  /// Sets the user's current location as the pickup location
  Future<void> _setCurrentLocationAsPickup() async {
    try {
      final locationData = await _location.getLocation();
      final latLng = LatLng(locationData.latitude!, locationData.longitude!);

      // Reverse geocode to get the address
      final url =
          "https://maps.googleapis.com/maps/api/geocode/json?latlng=${latLng.latitude},${latLng.longitude}&key=$_apiKey";
      final response = await http.get(Uri.parse(url));
      final data = jsonDecode(response.body);

      if (data["status"] == "OK" && data["results"].isNotEmpty) {
        final address = data["results"][0]["formatted_address"];

        setState(() {
          _pickupLocation = latLng;
          _pickupController.text = address;
        });

        // Move the camera to the user's location
        _mapController?.animateCamera(CameraUpdate.newLatLng(latLng));

        // Update markers
        _updateMarkers();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Could not fetch address for current location.")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error fetching current location: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('User Interface')),
      body: Column(
        children: [
          // Pickup Location Input
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                TextField(
                  controller: _pickupController,
                  decoration: InputDecoration(
                    hintText: "Enter pickup location",
                    border: OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _pickupController.clear();
                          _pickupLocation = null;
                          _updateMarkers();
                        });
                      },
                    ),
                    prefixIcon: IconButton(
                      icon: Icon(Icons.my_location),
                      onPressed: _setCurrentLocationAsPickup,
                    ),
                  ),
                  onChanged: (value) {
                    if (value.isNotEmpty) {
                      _fetchSuggestions(value, isPickup: true);
                    } else {
                      setState(() {
                        _pickupSuggestions.clear();
                      });
                    }
                  },
                ),
                if (_pickupSuggestions.isNotEmpty)
                  Container(
                    height: 100,
                    child: ListView.builder(
                      itemCount: _pickupSuggestions.length,
                      itemBuilder: (context, index) {
                        return ListTile(
                          title: Text(_pickupSuggestions[index]),
                          onTap: () {
                            _searchLocation(_pickupSuggestions[index], isPickup: true);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // Drop Location Input
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                TextField(
                  controller: _dropController,
                  decoration: InputDecoration(
                    hintText: "Enter drop location",
                    border: OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.clear),
                      onPressed: () {
                        setState(() {
                          _dropController.clear();
                          _dropLocation = null;
                          _updateMarkers();
                        });
                      },
                    ),
                  ),
                  onChanged: (value) {
                    if (value.isNotEmpty) {
                      _fetchSuggestions(value, isPickup: false);
                    } else {
                      setState(() {
                        _dropSuggestions.clear();
                      });
                    }
                  },
                ),
                if (_dropSuggestions.isNotEmpty)
                  Container(
                    height: 100,
                    child: ListView.builder(
                      itemCount: _dropSuggestions.length,
                      itemBuilder: (context, index) {
                        return ListTile(
                          title: Text(_dropSuggestions[index]),
                          onTap: () {
                            _searchLocation(_dropSuggestions[index], isPickup: false);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),

          // Google Map Display
          Expanded(
            child: GoogleMap(
              onMapCreated: _onMapCreated,
              initialCameraPosition: CameraPosition(
                target: LatLng(12.9716, 77.5946), // Default: Bangalore
                zoom: 14,
              ),
              markers: _markers,
              polylines: _polylines,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
            ),
          ),

          // Submit Button
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton(
              onPressed: _submitRideRequest,
              child: Text('Submit Ride Request'),
            ),
          ),
        ],
      ),
    );
  }
}
