import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Service to handle the dispatching of a 2-man crew (Mechanic + Assistant).
///
/// This service calls the backend API to perform the complex logic of finding
/// the nearest crew and creating jobs.
class CrewDispatchService {
  static const String _baseUrl = 'http://10.0.2.2:5050/api';

  Future<Map<String, dynamic>> dispatchCrew({
    required String requestId,
    required LatLng customerLocation,
    required String userId,
  }) async {
    final uri = Uri.parse('$_baseUrl/crew/dispatch');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'requestId': requestId,
        'userId': userId,
        'location': {
          'lat': customerLocation.latitude,
          'lng': customerLocation.longitude,
        }
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to dispatch crew: ${response.body}');
    }
  }
}
