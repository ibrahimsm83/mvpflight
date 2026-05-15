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

  /// When flight APIs omit coordinates, resolve airport via Google Geocoding.
  static Future<Map<String, double>?> geocodeAirport({
    required String iata,
    String city = '',
  }) async {
    final code = iata.trim().toUpperCase();
    if (code.isEmpty || code == 'N/A') return null;
    final query = city.trim().isNotEmpty
        ? '$city $code airport'
        : '$code airport';
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(query)}&key=$apiKey',
    );
    final response = await http.get(url);
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body);
    if (data['status'] != 'OK' ||
        data['results'] == null ||
        (data['results'] as List).isEmpty) {
      return null;
    }
    final loc = data['results'][0]['geometry']['location'];
    return {'lat': _toDouble(loc['lat']), 'lng': _toDouble(loc['lng'])};
  }

  @Deprecated('Use geocodeAirport')
  static Future<Map<String, double>?> geocodeDepartureAirport({
    required String iata,
    String city = '',
  }) => geocodeAirport(iata: iata, city: city);

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

  /// 5-day / 3-hour forecast at departure airport for [targetTime] (local).
  static Future<Map<String, dynamic>> getForecastForDeparture({
    required double lat,
    required double lng,
    required DateTime targetTime,
  }) async {
    final url = Uri.parse(
      'https://api.openweathermap.org/data/2.5/forecast?'
      'lat=$lat&lon=$lng&appid=$weatherKey&units=metric',
    );
    final response = await http.get(url);
    if (response.statusCode != 200) {
      throw Exception('Forecast API failed: ${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    final list = data['list'] as List?;
    if (list == null || list.isEmpty) {
      throw Exception('No forecast data');
    }

    Map<String, dynamic>? closest;
    int bestDiff = 1 << 30;
    for (final item in list) {
      final dtSec = _toInt(item['dt']);
      if (dtSec == 0) continue;
      final slot = DateTime.fromMillisecondsSinceEpoch(
        dtSec * 1000,
        isUtc: true,
      ).toLocal();
      final diff = slot.difference(targetTime).inMinutes.abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        closest = Map<String, dynamic>.from(item as Map);
        closest['_slot_local'] = slot.toIso8601String();
      }
    }
    if (closest == null) throw Exception('Could not match forecast slot');

    final weather = (closest['weather'] as List).first as Map;
    final condition = (weather['main'] ?? '').toString();
    final description = (weather['description'] ?? '').toString();
    final pop = ((closest['pop'] ?? 0) as num).toDouble();
    final popPercent = (pop * 100).round();

    final penalty = _rainDrivePenaltyMinutes(condition, pop);
    final rainExpected = penalty > 0;

    return {
      'condition': condition,
      'description': description,
      'pop': pop,
      'pop_percent': popPercent,
      'rain_expected': rainExpected,
      'drive_penalty_minutes': penalty,
      'forecast_slot': closest['_slot_local'],
      'target_time': targetTime.toIso8601String(),
    };
  }

  static int _rainDrivePenaltyMinutes(String condition, double pop) {
    final c = condition.toLowerCase();
    if (c.contains('thunder')) return 40;
    if (c.contains('rain')) {
      if (pop >= 0.5) return 30;
      if (pop >= 0.3) return 20;
      return 15;
    }
    if (c.contains('drizzle')) return 15;
    if (pop >= 0.5) return 25;
    if (pop >= 0.4) return 20;
    return 0;
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

  static Future<Map<String, dynamic>> getFlightData(
    String flightNo, {
    DateTime? flightDate,
  }) async {
    final normalized = flightNo.trim().toUpperCase();
    final date = flightDate ?? DateTime.now();
    final aviationData = await _fetchFromAviationstack(normalized, date);
    final airLabsData = await _fetchFromAirlabs(normalized, date);

    if (aviationData == null && airLabsData == null) {
      throw Exception(
        "Flight not found for ${_formatDateParam(date)}. Try another date or flight number.",
      );
    }
    final merged = _mergeFlightData(aviationData, airLabsData);
    merged['flight_date'] = _formatDateParam(date);
    alignTimesToSelectedDate(merged, date);
    return merged;
  }

  static String _formatDateParam(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// Forces departure/arrival onto [selectedDay] using API time-of-day only.
  static void alignTimesToSelectedDate(
    Map<String, dynamic> flight,
    DateTime selectedDay,
  ) {
    final depRaw = _parseDateTime(flight['departure']);
    final arrRaw = _parseDateTime(flight['arrival']);

    if (depRaw != null) {
      final dep = DateTime(
        selectedDay.year,
        selectedDay.month,
        selectedDay.day,
        depRaw.hour,
        depRaw.minute,
      );
      flight['departure'] = dep.toIso8601String();

      if (arrRaw != null) {
        final duration = arrRaw.isAfter(depRaw)
            ? arrRaw.difference(depRaw)
            : const Duration(hours: 2);
        flight['arrival'] = dep.add(duration).toIso8601String();
      }
    }
  }

  static void alignConnectingLeg(
    Map<String, dynamic> leg,
    DateTime hubArrival,
  ) {
    final depRaw = _parseDateTime(leg['departure']);
    final arrRaw = _parseDateTime(leg['arrival']);
    var dep = DateTime(
      hubArrival.year,
      hubArrival.month,
      hubArrival.day,
      depRaw?.hour ?? hubArrival.hour,
      depRaw?.minute ?? (hubArrival.minute + 90) % 60,
    );
    if (!dep.isAfter(hubArrival)) {
      dep = hubArrival.add(const Duration(hours: 2));
    }
    leg['departure'] = dep.toIso8601String();
    if (arrRaw != null && depRaw != null) {
      final duration = arrRaw.isAfter(depRaw)
          ? arrRaw.difference(depRaw)
          : const Duration(hours: 3);
      leg['arrival'] = dep.add(duration).toIso8601String();
    }
  }

  static DateTime? _parseDateTime(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty || s.toLowerCase() == 'n/a') return null;
    if (RegExp(r'^\d+$').hasMatch(s)) {
      final sec = int.tryParse(s);
      if (sec != null) {
        return DateTime.fromMillisecondsSinceEpoch(
          sec * 1000,
          isUtc: true,
        ).toLocal();
      }
    }
    final direct = DateTime.tryParse(s);
    if (direct != null) return direct.toLocal();
    return DateTime.tryParse(s.replaceFirst(' ', 'T'))?.toLocal();
  }

  static Future<Map<String, dynamic>?> _fetchFromAviationstack(
    String flightNo,
    DateTime flightDate,
  ) async {
    if (aviationStackKey == "YOUR_AVIATIONSTACK_KEY") return null;
    final dateStr = _formatDateParam(flightDate);
    final url = Uri.parse(
      "https://api.aviationstack.com/v1/flights?access_key=$aviationStackKey&flight_iata=$flightNo&flight_date=$dateStr",
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
      "terminal_changed": _toBool(
        flight['terminal_changed'] ?? departure['terminal_changed'],
      ),
      "terminal_change_source":
          flight['terminal_changed'] != null ||
              departure['terminal_changed'] != null
          ? "api"
          : "derived",
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
    DateTime flightDate,
  ) async {
    final schedule = await _fetchFromAirlabsSchedule(flightNo, flightDate);
    if (schedule != null) return schedule;

    final today = DateTime.now();
    final isToday = flightDate.year == today.year &&
        flightDate.month == today.month &&
        flightDate.day == today.day;
    if (!isToday) return null;

    final url =
        "https://airlabs.co/api/v9/flight?flight_iata=$flightNo&api_key=$flightKey";
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return null;

    final data = json.decode(response.body);
    if (data['response'] == null) return null;

    final flight = data['response'];
    return _mapAirlabsFlight(flight, provider: "airlabs-live");
  }

  static Future<Map<String, dynamic>?> _fetchFromAirlabsSchedule(
    String flightNo,
    DateTime flightDate,
  ) async {
    final url = Uri.parse(
      'https://airlabs.co/api/v9/schedules?flight_iata=$flightNo&api_key=$flightKey&limit=30',
    );
    final response = await http.get(url);
    if (response.statusCode != 200) return null;
    final data = json.decode(response.body);
    final list = data['response'];
    if (list is! List || list.isEmpty) return null;

    Map<String, dynamic>? best;
    int bestDiff = 1 << 30;
    for (final item in list) {
      if (item is! Map) continue;
      final dep = _parseDateTime(item['dep_time'] ?? item['dep_time_utc']);
      if (dep == null) continue;
      if (!_sameCalendarDay(dep, flightDate)) continue;
      final diff = dep.difference(flightDate).inMinutes.abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = Map<String, dynamic>.from(item);
      }
    }
    if (best == null) return null;
    return _mapAirlabsFlight(best, provider: "airlabs-schedule");
  }

  static bool _sameCalendarDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static Map<String, dynamic> _mapAirlabsFlight(
    Map flight, {
    required String provider,
  }) {
    return {
      "status": _normalizeStatus((flight['status'] ?? "scheduled").toString()),
      "departure": flight['dep_time'] ?? flight['dep_time_utc'] ?? "N/A",
      "arrival": flight['arr_time'] ?? flight['arr_time_utc'] ?? "N/A",
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
      "terminal_changed": _toBool(flight['terminal_changed']),
      "terminal_change_source": flight['terminal_changed'] != null
          ? "api"
          : "derived",
      "dep_lat": _toDouble(flight['dep_lat']),
      "dep_lng": _toDouble(flight['dep_lng']),
      "arr_lat": _toDouble(flight['arr_lat']),
      "arr_lng": _toDouble(flight['arr_lng']),
      "provider": provider,
      "airline": flight['airline_name'] ?? flight['airline'] ?? "",
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
    if (_isZeroCoord(a) && !_isZeroCoord(b)) return b;
    if (_isZeroCoord(b) && !_isZeroCoord(a)) return a;
    if (_hasValue(a) && !_isPlaceholder(a)) return a;
    if (_hasValue(b) && !_isPlaceholder(b)) return b;
    return _hasValue(a) ? a : b;
  }

  static bool _isZeroCoord(dynamic v) {
    if (v == null) return true;
    if (v is num) return v == 0;
    return v.toString().trim() == '0' || v.toString().trim() == '0.0';
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

  static bool _toBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    final v = value.toString().toLowerCase().trim();
    return v == 'true' || v == '1' || v == 'yes';
  }
}
