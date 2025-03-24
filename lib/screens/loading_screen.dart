import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'driver_tracking_screen.dart'; // Import the DriverTrackingScreen
import 'dart:math';

class LoadingScreen extends StatefulWidget {
  @override
  _LoadingScreenState createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  bool _isLoading = true;
  int? _requestId; // Store the ride request ID

  @override
  void initState() {
    super.initState();
    _fetchLatestRideRequestId(); // Fetch the latest ride request ID
  }

  // Fetch the latest ride request ID for the current user
  Future<void> _fetchLatestRideRequestId() async {
    try {
      // Replace `3` with the actual user ID
      final response = await _client
          .from('ride_request')
          .select('id')
          .eq('user_id', 3) // Filter by user ID
          .order('created_at', ascending: false) // Get the latest request
          .limit(1)
          .single();

      if (response != null) {
        setState(() {
          _requestId = response['id']; // Store the request ID
        });

        // Start checking the ride request status
        _checkRideRequestStatus();
      }
    } catch (e) {
      print('Error fetching latest ride request ID: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch ride request details. Please try again.')),
      );
    }
  }

  // Check the status of the ride request periodically
  Future<void> _checkRideRequestStatus() async {
  while (_isLoading && _requestId != null) {
    final rideRequest = await _checkRideRequestStatusInDB(_requestId!);

    if (rideRequest != null && rideRequest['ride_accepted'] == true) {
      // Ride request accepted, fetch driver details
      final driverDetails = await _fetchDriverDetailsInDB(_requestId!);

      if (driverDetails != null) {
        // Navigate to DriverTrackingScreen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => DriverTrackingScreen(
              driverLocation: LatLng(
                driverDetails['latitude'] ?? 0.0, // Default to 0.0 if latitude is missing
                driverDetails['longitude'] ?? 0.0, // Default to 0.0 if longitude is missing
              ),
              otp: driverDetails['otp'],
            ),
          ),
        );
        break; // Exit the loop
      }
    }

    // Wait for 5 seconds before checking again
    await Future.delayed(Duration(seconds: 5));
  }
}
  // Check if a ride request has been accepted by a driver
  // Check if a ride request has been accepted by a driver
Future<Map<String, dynamic>?> _checkRideRequestStatusInDB(int requestId) async {
  try {
    // Fetch the ride status from the ridestatus table
    final response = await _client
        .from('ridestatus')
        .select('ride_accepted, ride_cancelled, req_status')
        .eq('requestid', requestId);

    // Check if any rows were returned
    if (response.isNotEmpty) {
      final status = response[0]; // Take the first row (if multiple rows exist)

      // Check if the ride has been accepted
      if (status['ride_accepted'] == true) {
        return status;
      }
    }
    return null; // No matching rows or ride not accepted
  } catch (e) {
    print('Error checking ride request status: $e');
    return null;
  }
}

  // Fetch driver details and OTP for an accepted ride request
  // Fetch driver details and OTP for an accepted ride request
Future<Map<String, dynamic>?> _fetchDriverDetailsInDB(int requestId) async {
  try {
    // Fetch the driver ID and OTP from the ridestatus and ride_request tables
    final response = await _client
        .from('ridestatus')
        .select('driverid, ride_request!inner(otp)')
        .eq('requestid', requestId);

    if (response.isNotEmpty) {
      final driverId = response[0]['driverid']; // Take the first row
      final otp = response[0]['ride_request']['otp']; // Fetch OTP from ride_request

      // Fetch driver details from the driver table
      final driverDetails = await _client
          .from('driver') // Correct table name
          .select('drivername, phoneno, latitude, longitude') // Correct column names
          .eq('driverid', driverId) // Correct column name
          .single();

      return {
        ...driverDetails,
        'otp': otp, // Include the OTP in the response
      };
    }
    return null; // No matching rows
  } catch (e) {
    print('Error fetching driver details: $e');
    return null;
  }
}

  // Insert a new ride request with OTP
  Future<void> _insertRideRequest({
    required int userId,
    required String userName,
    required String userPhno,
    required double pickUpLat,
    required double pickUpLng,
    required double dropLat,
    required double dropLng,
    required String dropAddress,
    required String pickupAddress,
  }) async {
    try {
      // Generate a random 6-digit OTP
      final otp = _generateOTP();

      await _client.from('ride_request').insert({
        'user_id': userId,
        'user_name': userName,
        'user_phno': userPhno,
        'pick_up_lat': pickUpLat,
        'pick_up_lng': pickUpLng,
        'drop_lat': dropLat,
        'drop_lng': dropLng,
        'drop_address': dropAddress,
        'pick_up_address': pickupAddress,
        'otp': otp, // Store the OTP in the database
      });
    } catch (e) {
      print('Error inserting ride request: $e');
      rethrow;
    }
  }

  // Generate a random 6-digit OTP
  String _generateOTP() {
    final random = Random();
    final otp = 100000 + random.nextInt(900000); // Generates a number between 100000 and 999999
    return otp.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(), // Loading spinner
            SizedBox(height: 20), // Spacing
            Text(
              'Waiting for a driver to accept your ride...',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}