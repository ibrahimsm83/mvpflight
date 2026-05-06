import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String apiKey = "AIzaSyCDGe4wXXZ1gwVU2W1Qz66g5Rf0t-df9NQ";
  static const String weatherKey = "d93ae92db1225dd97aae37e416568e8b";
  static const String aviationStackKey = "9d3b48b554e96aac9cffc63fe1c61481";
  static const String flightKey = "9cab6e82-5e89-42a5-9b4b-7e278c4a874c";

  static Future<Map<String, String>> getDistanceMatrix(
    double originLat,
    double originLng,
    double destLat,
    double destLng,
  ) async {
    final url = Uri.parse(
      "https://routes.googleapis.com/directions/v2:computeRoutes",
    );

    final response = await http.post(
      url,
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask":
            "routes.distanceMeters,routes.duration,routes.staticDuration",
      },
      body: jsonEncode({
        "origin": {
          "location": {
            "latLng": {"latitude": originLat, "longitude": originLng},
          },
        },
        "destination": {
          "location": {
            "latLng": {"latitude": destLat, "longitude": destLng},
          },
        },
        "travelMode": "DRIVE",
        "routingPreference": "TRAFFIC_AWARE",
      }),
    );

    if (response.statusCode != 200) {
      throw Exception("HTTP error: ${response.statusCode}");
    }

    final data = jsonDecode(response.body);

    if (data['routes'] == null || data['routes'].isEmpty) {
      throw Exception("No routes found");
    }

    final route = data['routes'][0];
    double distanceKm = route['distanceMeters'] / 1000;
    Duration duration = parseDuration(route['duration']);
    Duration staticDuration = parseDuration(route['staticDuration']);

    return {
      "distance": "${distanceKm.toStringAsFixed(2)} km",
      "duration": formatDuration(staticDuration),
      "traffic_duration": formatDuration(duration),
    };
  }

  static Duration parseDuration(String duration) {
    final seconds = int.parse(duration.replaceAll("s", ""));
    return Duration(seconds: seconds);
  }

  static String formatDuration(Duration d) {
    int hours = d.inHours;
    int minutes = d.inMinutes % 60;

    if (hours > 0) {
      return "$hours h $minutes min";
    } else {
      return "$minutes min";
    }
  }

  static Future<Map<String, dynamic>> getWeather(double lat, double lng) async {
    final url = Uri.parse(
      "https://api.openweathermap.org/data/2.5/weather?"
      "lat=$lat&lon=$lng&appid=$weatherKey&units=metric",
    );

    final response = await http.get(url);
    if (response.statusCode != 200) {
      throw Exception("Weather API failed: ${response.statusCode}");
    }
    final data = jsonDecode(response.body);

    return {
      "temp": data['main']['temp'],
      "condition": data['weather'][0]['main'],
      "description": data['weather'][0]['description'],
      "wind": data['wind']['speed'],
      "visibility": data['visibility'],
      "humidity": data['main']['humidity'],
    };
  }

  static Future<Map<String, dynamic>> getWeatherByCity(String city) async {
    final url = Uri.parse(
      "https://api.openweathermap.org/data/2.5/weather?"
      "q=$city&appid=$weatherKey&units=metric",
    );
    final response = await http.get(url);
    if (response.statusCode != 200) {
      throw Exception("Weather by city failed: ${response.statusCode}");
    }
    final data = jsonDecode(response.body);
    return {
      "temp": data['main']['temp'],
      "condition": data['weather'][0]['main'],
      "description": data['weather'][0]['description'],
      "wind": data['wind']['speed'],
      "visibility": data['visibility'],
      "humidity": data['main']['humidity'],
    };
  }

  static Future<Map<String, dynamic>> getFlightData(String flightNo) async {
    final normalized = flightNo.trim().toUpperCase();
    final aviationData = await _fetchFromAviationstack(normalized);
    final airLabsData = await _fetchFromAirlabs(normalized);

    if (aviationData == null && airLabsData == null) {
      throw Exception("Flight not found on both providers");
    }
    return _mergeFlightData(aviationData, airLabsData);
  }

  static Future<Map<String, dynamic>?> _fetchFromAviationstack(
    String flightNo,
  ) async {
    if (aviationStackKey == "YOUR_AVIATIONSTACK_KEY") return null;
    final url = Uri.parse(
      "https://api.aviationstack.com/v1/flights?access_key=$aviationStackKey&flight_iata=$flightNo",
    );
    final response = await http.get(url);
    if (response.statusCode != 200) return null;

    final body = json.decode(response.body);
    if (body['data'] == null || body['data'] is! List || body['data'].isEmpty) {
      return null;
    }

    final flight = body['data'][0];
    final departure = flight['departure'] ?? {};
    final arrival = flight['arrival'] ?? {};
    final airline = flight['airline'] ?? {};

    final status = _normalizeStatus((flight['flight_status'] ?? '').toString());
    final delayMin = _toInt(departure['delay']);

    return {
      "status": status.isEmpty ? "Unknown" : status,
      "departure": departure['scheduled'] ?? "N/A",
      "arrival": arrival['scheduled'] ?? "N/A",
      "dep_iata": departure['iata'] ?? "N/A",
      "arr_iata": arrival['iata'] ?? "N/A",
      "dep_country": departure['timezone'] ?? "",
      "arr_country": arrival['timezone'] ?? "",
      "dep_city": departure['airport'] ?? "",
      "arr_city": arrival['airport'] ?? "",
      "dep_terminal": departure['terminal'] ?? "N/A",
      "arr_terminal": arrival['terminal'] ?? "N/A",
      "gate": departure['gate'] ?? "N/A",
      "delay": "$delayMin",
      "terminal_changed": (departure['terminal'] ?? "").toString().isEmpty,
      "dep_lat": 0.0,
      "dep_lng": 0.0,
      "arr_lat": 0.0,
      "arr_lng": 0.0,
      "provider": "aviationstack",
      "airline": airline['name'] ?? "",
    };
  }

  static Future<Map<String, dynamic>?> _fetchFromAirlabs(
    String flightNo,
  ) async {
    final url =
        "https://airlabs.co/api/v9/flight?flight_iata=$flightNo&api_key=$flightKey";
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return null;

    final data = json.decode(response.body);
    if (data['response'] == null) return null;

    final flight = data['response'];
    return {
      "status": _normalizeStatus((flight['status'] ?? "Unknown").toString()),
      "departure": flight['dep_time'] ?? "N/A",
      "arrival": flight['arr_time'] ?? "N/A",
      "dep_iata": flight['dep_iata'] ?? "N/A",
      "arr_iata": flight['arr_iata'] ?? "N/A",
      "dep_country": flight['dep_country'] ?? "",
      "arr_country": flight['arr_country'] ?? "",
      "dep_city": flight['dep_city'] ?? "",
      "arr_city": flight['arr_city'] ?? "",
      "dep_terminal": flight['dep_terminal'] ?? "N/A",
      "arr_terminal": flight['arr_terminal'] ?? "N/A",
      "gate": flight['dep_gate'] ?? "N/A",
      "delay": "${flight['delayed'] ?? 0}",
      "terminal_changed": (flight['dep_terminal'] ?? "").toString().isEmpty,
      "dep_lat": _toDouble(flight['dep_lat']),
      "dep_lng": _toDouble(flight['dep_lng']),
      "arr_lat": _toDouble(flight['arr_lat']),
      "arr_lng": _toDouble(flight['arr_lng']),
      "provider": "airlabs",
      "airline": flight['airline_name'] ?? "",
    };
  }

  static Map<String, dynamic> _mergeFlightData(
    Map<String, dynamic>? aviation,
    Map<String, dynamic>? airlabs,
  ) {
    if (aviation == null) return _withDelayLabel(airlabs!);
    if (airlabs == null) return _withDelayLabel(aviation);

    final merged = <String, dynamic>{};
    for (final key in {...aviation.keys, ...airlabs.keys}) {
      final a = aviation[key];
      final b = airlabs[key];
      merged[key] = _pickBetterValue(a, b);
    }

    merged['provider'] = "aviationstack+airlabs";
    final bestStatus = _pickStatus(aviation['status'], airlabs['status']);
    merged['status'] = bestStatus;
    return _withDelayLabel(merged);
  }

  static dynamic _pickBetterValue(dynamic a, dynamic b) {
    if (_hasValue(a) && !_isPlaceholder(a)) return a;
    if (_hasValue(b) && !_isPlaceholder(b)) return b;
    return _hasValue(a) ? a : b;
  }

  static String _pickStatus(dynamic a, dynamic b) {
    final sa = (a ?? "").toString().trim();
    final sb = (b ?? "").toString().trim();
    if (sa == "delayed" || sb == "delayed") return "delayed";
    if (sa == "active" || sb == "active") return "active";
    if (sa == "scheduled" || sb == "scheduled") return "scheduled";
    if (sa.isNotEmpty) return sa;
    return sb.isNotEmpty ? sb : "unknown";
  }

  static Map<String, dynamic> _withDelayLabel(Map<String, dynamic> flight) {
    final delayMins = _toInt(flight['delay']);
    final status = (flight['status'] ?? "unknown").toString();
    if (delayMins > 0 || status == "delayed") {
      flight['delay_note'] = "Delayed by $delayMins min";
    } else {
      flight['delay_note'] = "No delay reported";
    }
    return flight;
  }

  static bool _hasValue(dynamic v) =>
      v != null && v.toString().trim().isNotEmpty;

  static bool _isPlaceholder(dynamic v) {
    final s = v.toString().trim().toLowerCase();
    return s == "n/a" || s == "unknown" || s == "0";
  }

  static String _normalizeStatus(String raw) {
    final s = raw.toLowerCase().trim();
    if (s.contains("cancel")) return "cancelled";
    if (s.contains("delay")) return "delayed";
    if (s.contains("active") || s.contains("en-route")) return "active";
    if (s.contains("land")) return "landed";
    if (s.contains("schedule")) return "scheduled";
    return s.isEmpty ? "unknown" : s;
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  static int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }
}
