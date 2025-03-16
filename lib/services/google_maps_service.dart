import 'package:http/http.dart' as http;
import 'dart:convert';

class GoogleMapsService {
  final String _googleApiKey = 'AIzaSyAvibCYQuoqU1BNqfWV0QkTXvT39-Wz954'; // Replace with your Google Maps API key
  final String _geminiApiKey = 'AIzaSyCqLXMSz5s4Qdl0Uyrqc9H5wsyMuSYASLw'; // Replace with your Gemini API key

  /// Fetches the category and priority of a location using Google Places API
  Future<String> getLocationCategory(double lat, double lng) async {
    final url =
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=$lat,$lng&radius=25&key=$_googleApiKey';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);

      if (data['results'].isNotEmpty) {
        // Iterate through nearby places to determine the highest priority
        String bestPriority = 'Tier 4';
        String bestPlaceType = 'Unknown';

        for (var place in data['results']) {
          List<dynamic> types = place['types'] as List<dynamic>;
          String priority = _determinePriority(types);
          String placeType = types.isNotEmpty ? types[0] : 'Unknown';

          // If Tier 1 is found, return immediately
          if (priority == 'Tier 1') {
            return 'Tier 1|$placeType';
          }

          // Otherwise, keep track of the highest priority
          if (_isHigherPriority(priority, bestPriority)) {
            bestPriority = priority;
            bestPlaceType = placeType;
          }
        }

        return '$bestPriority|$bestPlaceType';
      }
    }

    // Default to Tier 4 if no places are found
    return 'Tier 4|Unknown';
  }

  /// Determines the priority based on the place type
  String _determinePriority(List<dynamic> types) {
    // Tier 1: Emergency & Life-Critical Locations
    if (types.contains('hospital') ||
        types.contains('doctor') ||
        types.contains('pharmacy') ||
        types.contains('ambulance_station') ||
        types.contains('police') ||
        types.contains('fire_station') ||
        types.contains('blood_bank') ||
        types.contains('natural_feature') || // Flood zones & fire-prone areas
        types.contains('disaster_response')) {
      return 'Tier 1';
    }

    // Tier 2: High-Demand Transport & Public Hubs
    if (types.contains('train_station') ||
        types.contains('bus_station') ||
        types.contains('airport') ||
        types.contains('subway_station') ||
        types.contains('courthouse') ||
        types.contains('embassy') ||
        types.contains('government_office') ||
        types.contains('school') ||
        types.contains('university')) {
      return 'Tier 2';
    }

    // Tier 3: Economic & Business Hotspots
    if (types.contains('bank') ||
        types.contains('finance') ||
        types.contains('industrial_area') ||
        types.contains('business_center') ||
        types.contains('shopping_mall') ||
        types.contains('stadium') ||
        types.contains('convention_center')) {
      return 'Tier 3';
    }

    // Tier 4: Community & Special Events (Lowest Priority)
    if (types.contains('place_of_worship') ||
        types.contains('church') ||
        types.contains('mosque') ||
        types.contains('hindu_temple') ||
        types.contains('synagogue') ||
        types.contains('museum') ||
        types.contains('amusement_park') ||
        types.contains('tourist_attraction') ||
        types.contains('theater')) {
      return 'Tier 4';
    }

    // Default to Tier 4 if no matches
    return 'Tier 4';
  }

  /// Helper function to compare priority levels
  bool _isHigherPriority(String newPriority, String currentPriority) {
    List<String> priorityOrder = ['Tier 1', 'Tier 2', 'Tier 3', 'Tier 4'];
    return priorityOrder.indexOf(newPriority) < priorityOrder.indexOf(currentPriority);
  }

  /// Converts latitude and longitude into a human-readable address
  Future<String> getAddressFromLatLng(double lat, double lng) async {
    final url =
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$_googleApiKey';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['results'].isNotEmpty) {
        return data['results'][0]['formatted_address'];
      }
    }

    return 'Address not found';
  }

  /// Fetches the category of a location using Gemini API
  /// Fetches the category and tier of a location using Gemini API
Future<Map<String, String>> getLocationCategoryAndTier(String locationName) async {
  final url = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$_geminiApiKey';

  final headers = {
    'Content-Type': 'application/json',
  };

  final promptText = '''
  Categorize the following location "$locationName" according to these tiers:
  
  Tier 1: Emergency & Life-Critical Locations
  - Healthcare & Medical Facilities (Hospitals, Clinics, Ambulance Support Points, Pharmacies, Blood Banks)
  - Law Enforcement & Security (Police Stations, Fire Stations, Disaster Response Centers, High-Security Zones)
  - Natural Disaster & Crisis Zones (Flood-Prone Areas, Fire-Prone Zones)
  
  Tier 2: High-Demand Transport & Public Hubs
  - Public Transport Hubs (Railway Stations, Metro & Bus Terminals, Airports)
  - Government & Legal Centers (Courts, Legal Offices, Passport & RTO Offices)
  - Educational Institutions (Schools, Colleges, Examination Centers)
  
  Tier 3: Economic & Business Hotspots
  - Corporate & Industrial Zones (IT Parks, Business Districts, Factories, Banking Hubs)
  - Major Commercial Centers (Shopping Malls, Markets, Large Event & Stadium Venues)
  
  Tier 4: Community & Special Events
  - Religious & Cultural Sites (Temples, Mosques, Churches, Gurudwaras, Religious Gatherings)
  - Recreational & Entertainment Venues (Theaters, Concert Halls, Theme Parks, Tourist Attractions)
  
  Return only the response in this exact format without explanation: "Tier X|Category" where X is 1, 2, 3, or 4, and Category is a single word describing the location type.
  ''';

  final body = jsonEncode({
    "contents": [
      {
        "parts": [
          {"text": promptText}
        ]
      }
    ]
  });

  try {
    final response = await http.post(Uri.parse(url), headers: headers, body: body);

    print('Gemini API Response: ${response.statusCode} - ${response.body}'); // Log the response

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data.containsKey('candidates') && data['candidates'].isNotEmpty) {
        final result = data['candidates'][0]['content']['parts'][0]['text'].trim();
        
        // Parse the result in format "Tier X|Category"
        List<String> parts = result.split('|');
        if (parts.length == 2) {
          return {
            'tier': parts[0].trim(),
            'category': parts[1].trim().toLowerCase()
          };
        } else {
          // Handle unexpected format, try to extract tier and category
          if (result.toLowerCase().contains('tier 1')) {
            return {'tier': 'Tier 1', 'category': 'emergency'};
          } else if (result.toLowerCase().contains('tier 2')) {
            return {'tier': 'Tier 2', 'category': 'transport_hub'};
          } else if (result.toLowerCase().contains('tier 3')) {
            return {'tier': 'Tier 3', 'category': 'business'};
          } else {
            return {'tier': 'Tier 4', 'category': 'community'};
          }
        }
      } else {
        print('Category not found in API response');
        return {'tier': 'Tier 4', 'category': 'unknown'};
      }
    } else {
      print('Failed to load category: ${response.statusCode} - ${response.body}');
      return {'tier': 'Tier 4', 'category': 'unknown'};
    }
  } catch (e) {
    print('Failed to call Gemini API: $e');
    return {'tier': 'Tier 4', 'category': 'unknown'};
  }
}
}