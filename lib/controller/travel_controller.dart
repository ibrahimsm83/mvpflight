import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';

class TravelController extends GetxController {
  final TextEditingController homeController = TextEditingController();
  final FocusNode homeFocus = FocusNode();
  final TextEditingController flightController = TextEditingController();
  final TextEditingController connectionFlightController =
      TextEditingController();

  final homeLat = 0.0.obs;
  final homeLng = 0.0.obs;
  final destLat = 0.0.obs;
  final destLng = 0.0.obs;

  final distance = ''.obs;
  final duration = ''.obs;
  final traficDuration = ''.obs;
  final leaveHomeAt = ''.obs;
  final recommendedBuffer = ''.obs;
  final terminalSwitchPenaltyText = ''.obs;
  final terminalChangeInfo = ''.obs;
  final airportProcessTime = ''.obs;
  final boardingTime = ''.obs;
  final homeToAirportTotal = ''.obs;
  final totalJourneyDuration = ''.obs;
  final lateWarning = ''.obs;
  final timingStatus = ''.obs;
  final isLoading = false.obs;
  final isConnecting = false.obs;
  final flights = <Map<String, dynamic>>[].obs;
  final flightRisk = ''.obs;
  final weatherDesc = ''.obs;
  final depWeather = ''.obs;
  final arrWeather = ''.obs;
  final depWeatherLabel = ''.obs;
  final arrWeatherLabel = ''.obs;
  final weatherCards = <Map<String, String>>[].obs;
  final departureAirportLabel = ''.obs;
  final selectedFlightDate = Rx<DateTime>(
    DateTime(
      DateTime.now().year,
      DateTime.now().month,
      DateTime.now().day,
    ),
  );
  final selectedFlightDateLabel = ''.obs;
  final flightMissedWarning = ''.obs;
  final timeUntilDeparture = ''.obs;
  final timeUntilLeaveHome = ''.obs;
  final rainWarning = ''.obs;
  final rainForecastInfo = ''.obs;
  final rainDrivePenalty = ''.obs;
  final adjustedDriveTime = ''.obs;
  Duration _rainPenaltyDuration = Duration.zero;
  DateTime? _leaveAtDateTime;
  Timer? _warningTimer;

  @override
  void onClose() {
    _warningTimer?.cancel();
    homeController.dispose();
    flightController.dispose();
    connectionFlightController.dispose();
    homeFocus.dispose();
    super.onClose();
  }

  Future<void> getPlaceLatLng(String placeId) async {
    try {
      final url = Uri.parse(
        "https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=${ApiService.apiKey}",
      );
      final response = await http.get(url);
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body);
      final location = data['result']['geometry']['location'];
      final double lat = location['lat'];
      final double lng = location['lng'];

      homeLat.value = lat;
      homeLng.value = lng;
    } catch (_) {
      Get.snackbar("Location Error", "Failed to resolve selected place.");
    }
  }

  Future<void> getDistance() async {
    if (homeLat.value == 0.0 || destLat.value == 0.0) {
      throw Exception(
        "Select your home location and ensure the flight has a departure airport.",
      );
    }
    final result = await ApiService.getDistanceMatrix(
      homeLat.value,
      homeLng.value,
      destLat.value,
      destLng.value,
    );
    distance.value = result['distance'] ?? '';
    duration.value = result['duration'] ?? '';
    traficDuration.value = result['traffic_duration'] ?? '';
  }

  Future<void> analyzeWeather() async {
    if (destLat.value == 0.0 || destLng.value == 0.0) return;
    final result = await ApiService.getWeather(destLat.value, destLng.value);
    weatherDesc.value = (result['description'] ?? '').toString();

    final double wind = ((result['wind'] ?? 0.0) as num).toDouble() * 3.6;
    final int visibility = ((result['visibility'] ?? 10000) as num).toInt();
    final String condition = (result['condition'] ?? '').toString();

    if (condition.contains("Thunderstorm")) {
      flightRisk.value = "High Delay Risk (Thunderstorm)";
    } else if (condition.contains("Rain")) {
      flightRisk.value = "Possible Delay (Rain)";
    } else if (visibility < 2000) {
      flightRisk.value = "Possible Delay (Low Visibility)";
    } else if (wind > 30) {
      flightRisk.value = "Possible Delay (Strong Winds)";
    } else {
      flightRisk.value = "Weather Looks Stable";
    }
  }

  void _normalizeAllFlightTimes() {
    if (flights.isEmpty) return;
    ApiService.alignTimesToSelectedDate(
      flights.first,
      selectedFlightDate.value,
    );
    if (flights.length > 1) {
      final hubArr = _parseApiDate((flights[0]['arrival'] ?? '').toString());
      if (hubArr != null) {
        ApiService.alignConnectingLeg(flights[1], hubArr);
      } else {
        ApiService.alignTimesToSelectedDate(
          flights[1],
          selectedFlightDate.value,
        );
      }
    }
  }

  Future<void> _analyzeSegmentWeather() async {
    if (flights.isEmpty) return;
    weatherCards.clear();
    final first = flights.first;
    final depIata = (first['dep_iata'] ?? 'DEP').toString();
    final arrIata = (first['arr_iata'] ?? 'ARR').toString();
    depWeatherLabel.value = depIata;
    arrWeatherLabel.value = arrIata;

    final depText = await _fetchWeatherForStop(
      title: '$depIata — Departure airport',
      iata: depIata,
      lat: _readCoord(first['dep_lat']),
      lng: _readCoord(first['dep_lng']),
      city: (first['dep_city'] ?? '').toString(),
      targetTime: _parseApiDate((first['departure'] ?? '').toString()),
    );
    depWeather.value = depText;
    weatherCards.add({'title': '$depIata — Departure airport', 'body': depText});

    final arrText = await _fetchWeatherForStop(
      title: '$arrIata — Destination',
      iata: arrIata,
      lat: _readCoord(first['arr_lat']),
      lng: _readCoord(first['arr_lng']),
      city: (first['arr_city'] ?? '').toString(),
      targetTime: _parseApiDate((first['arrival'] ?? '').toString()),
    );
    arrWeather.value = arrText;
    weatherCards.add({'title': '$arrIata — Destination', 'body': arrText});

    if (flights.length > 1) {
      final second = flights[1];
      final finalIata = (second['arr_iata'] ?? 'ARR').toString();
      final finalText = await _fetchWeatherForStop(
        title: '$finalIata — Final destination (connecting)',
        iata: finalIata,
        lat: _readCoord(second['arr_lat']),
        lng: _readCoord(second['arr_lng']),
        city: (second['arr_city'] ?? '').toString(),
        targetTime: _parseApiDate((second['arrival'] ?? '').toString()),
      );
      weatherCards.add({
        'title': '$finalIata — Final destination',
        'body': finalText,
      });
    }
  }

  Future<void> _ensureAllAirportCoordinates() async {
    for (final flight in flights) {
      await _ensureAirportCoordinates(flight, isArrival: false);
      await _ensureAirportCoordinates(flight, isArrival: true);
    }
  }

  Future<void> _ensureAirportCoordinates(
    Map<String, dynamic> flight, {
    required bool isArrival,
  }) async {
    final latKey = isArrival ? 'arr_lat' : 'dep_lat';
    final lngKey = isArrival ? 'arr_lng' : 'dep_lng';
    final iataKey = isArrival ? 'arr_iata' : 'dep_iata';
    final cityKey = isArrival ? 'arr_city' : 'dep_city';

    if (_readCoord(flight[latKey]) != 0.0 && _readCoord(flight[lngKey]) != 0.0) {
      return;
    }

    final iata = (flight[iataKey] ?? '').toString();
    final city = (flight[cityKey] ?? '').toString();
    final resolved = await ApiService.geocodeAirport(iata: iata, city: city);
    if (resolved != null) {
      flight[latKey] = resolved['lat'];
      flight[lngKey] = resolved['lng'];
    }
  }

  Future<String> _fetchWeatherForStop({
    required String title,
    required String iata,
    required double lat,
    required double lng,
    required String city,
    DateTime? targetTime,
  }) async {
    try {
      double useLat = lat;
      double useLng = lng;

      if (useLat == 0.0 || useLng == 0.0) {
        final geo = await ApiService.geocodeAirport(iata: iata, city: city);
        if (geo != null) {
          useLat = geo['lat']!;
          useLng = geo['lng']!;
        }
      }

      if (targetTime != null &&
          targetTime.isAfter(DateTime.now()) &&
          useLat != 0.0 &&
          useLng != 0.0) {
        final forecast = await ApiService.getForecastForDeparture(
          lat: useLat,
          lng: useLng,
          targetTime: targetTime,
        );
        return "Forecast: ${forecast['condition']} — ${forecast['description']} "
            "(${forecast['pop_percent']}% rain)";
      }
      if (useLat != 0.0 && useLng != 0.0) {
        final w = await ApiService.getWeather(useLat, useLng);
        return "${w['condition']} (${w['description']}) ${w['temp']}C";
      }
      if (iata.isNotEmpty && iata != 'N/A') {
        final w = await ApiService.getWeatherByCity(iata);
        return "${w['condition']} (${w['description']}) ${w['temp']}C";
      }
      if (city.isNotEmpty) {
        final w = await ApiService.getWeatherByCity(city);
        return "${w['condition']} (${w['description']}) ${w['temp']}C";
      }
    } catch (e) {
      return 'Weather unavailable ($iata): ${e.toString().replaceFirst('Exception: ', '')}';
    }
    return 'Not available — enable Geocoding API or check OpenWeather key';
  }

  Future<void> loadTripSummary() async {
    try {
      isLoading.value = true;
      flights.clear();
      departureAirportLabel.value = '';
      distance.value = '';
      duration.value = '';
      traficDuration.value = '';
      rainWarning.value = '';
      rainForecastInfo.value = '';
      rainDrivePenalty.value = '';
      adjustedDriveTime.value = '';
      _rainPenaltyDuration = Duration.zero;
      flightMissedWarning.value = '';
      timeUntilDeparture.value = '';
      timeUntilLeaveHome.value = '';
      if (flightController.text.trim().isEmpty) {
        throw Exception("Please enter at least one flight number.");
      }
      if (homeLat.value == 0.0 || homeLng.value == 0.0) {
        throw Exception("Please select your home location.");
      }

      final firstFlight = await ApiService.getFlightData(
        flightController.text.trim(),
        flightDate: selectedFlightDate.value,
      );
      await _applyDepartureAirportFromFlight(firstFlight);
      flights.add(firstFlight);

      if (isConnecting.value &&
          connectionFlightController.text.trim().isNotEmpty) {
        final secondFlight = await ApiService.getFlightData(
          connectionFlightController.text.trim(),
          flightDate: selectedFlightDate.value,
        );
        flights.add(secondFlight);
      }
      _normalizeAllFlightTimes();
      await _ensureAllAirportCoordinates();

      try {
        await getDistance();
      } catch (_) {
        distance.value = "Unavailable";
        duration.value = "Unavailable";
        traficDuration.value = "0 min";
        Get.snackbar(
          "Route",
          "Could not get drive time; buffer uses 0 min for traffic.",
        );
      }
      try {
        await _applyDepartureDayRainForecast();
      } catch (_) {
        rainForecastInfo.value = "Travel-day forecast unavailable";
      }
      try {
        await analyzeWeather();
      } catch (_) {
        flightRisk.value = "";
        weatherDesc.value = "Weather unavailable";
      }
      try {
        await _analyzeSegmentWeather();
      } catch (_) {
        depWeather.value = "";
        arrWeather.value = "";
      }
      _computeLeaveHomeTime();
    } catch (e) {
      Get.snackbar("Trip Error", e.toString().replaceFirst("Exception: ", ""));
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _applyDepartureAirportFromFlight(
    Map<String, dynamic> flight,
  ) async {
    double lat = _readCoord(flight['dep_lat']);
    double lng = _readCoord(flight['dep_lng']);
    final iata = (flight['dep_iata'] ?? '').toString();
    final city = (flight['dep_city'] ?? '').toString();

    if (lat == 0.0 || lng == 0.0) {
      final resolved = await ApiService.geocodeAirport(
        iata: iata,
        city: city,
      );
      if (resolved == null) {
        throw Exception(
          "Departure airport has no coordinates in flight data and Geocoding failed. "
          "Enable Geocoding API for your Google key, or pick a flight where AirLabs returns dep_lat/dep_lng.",
        );
      }
      lat = resolved['lat']!;
      lng = resolved['lng']!;
      flight['dep_lat'] = lat;
      flight['dep_lng'] = lng;
    }

    destLat.value = lat;
    destLng.value = lng;
    departureAirportLabel.value = city.isNotEmpty
        ? '$iata — $city (from flight)'
        : '$iata airport (from flight)';
  }

  double _readCoord(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  Future<void> _applyDepartureDayRainForecast() async {
    if (flights.isEmpty) return;
    final depText = (flights.first['departure'] ?? '').toString();
    final departure = _parseApiDate(depText);
    if (departure == null) {
      rainForecastInfo.value = "Set a flight with valid departure time for rain forecast";
      return;
    }

    final lat = destLat.value;
    final lng = destLng.value;
    if (lat == 0.0 || lng == 0.0) return;

    // Forecast around when user would drive (~3h before departure).
    final travelWindow = departure.subtract(const Duration(hours: 3));

    final forecast = await ApiService.getForecastForDeparture(
      lat: lat,
      lng: lng,
      targetTime: travelWindow,
    );

    final penaltyMin = _toInt(forecast['drive_penalty_minutes']);
    _rainPenaltyDuration = Duration(minutes: penaltyMin);
    final iata = (flights.first['dep_iata'] ?? 'DEP').toString();
    final pop = forecast['pop_percent'];
    final desc = forecast['description'];
    final slot = forecast['forecast_slot'];

    rainForecastInfo.value =
        "$iata on travel day (~${travelWindow.hour.toString().padLeft(2, '0')}:${travelWindow.minute.toString().padLeft(2, '0')}): "
        "${forecast['condition']} — $desc ($pop% rain chance, forecast slot $slot)";

    if (forecast['rain_expected'] == true) {
      rainDrivePenalty.value = _formatDuration(_rainPenaltyDuration);
      final base = traficDuration.value.trim().isEmpty
          ? Duration.zero
          : _parseHumanDuration(traficDuration.value);
      adjustedDriveTime.value = _formatDuration(base + _rainPenaltyDuration);
      rainWarning.value =
          "Rain expected on your travel day. Extra $penaltyMin min added to drive time "
          "(traffic is usually slower than a normal dry day). Leave earlier.";
      final cond = (forecast['condition'] ?? '').toString();
      if (cond.toLowerCase().contains('thunder')) {
        flightRisk.value = "High delay risk — thunderstorm forecast on travel day";
      } else {
        flightRisk.value =
            "Possible delay — rain forecast ($pop% chance) on travel day";
      }
    } else {
      rainDrivePenalty.value = "0 min";
      rainWarning.value = "";
      adjustedDriveTime.value = traficDuration.value;
    }
  }

  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  void _computeLeaveHomeTime() {
    if (flights.isEmpty) return;

    final depText = (flights.first['departure'] ?? '').toString();
    final DateTime? departure = _parseApiDate(depText);

    final Duration baseTraffic = traficDuration.value.trim().isEmpty
        ? Duration.zero
        : _parseHumanDuration(traficDuration.value);
    final Duration traffic = baseTraffic + _rainPenaltyDuration;
    if (_rainPenaltyDuration > Duration.zero) {
      adjustedDriveTime.value = _formatDuration(traffic);
    }
    const Duration airportBuffer = Duration(hours: 3);

    final bool terminalChanged =
        (flights.first['terminal_changed'] ?? false) == true;
    final Duration terminalSwitchPenalty = terminalChanged
        ? const Duration(minutes: 30)
        : Duration.zero;
    terminalSwitchPenaltyText.value = _formatDuration(terminalSwitchPenalty);
    final source = (flights.first['terminal_change_source'] ?? 'derived')
        .toString();
    terminalChangeInfo.value =
        "Terminal changed: ${terminalChanged ? 'Yes' : 'No'} (source: $source)";

    const Duration checkIn = Duration(minutes: 60);
    const Duration security = Duration(minutes: 55);
    const Duration boarding = Duration(minutes: 45);
    const Duration gateWalk = Duration(minutes: 20);
    const Duration uncertainty = Duration(minutes: 20);

    final totalAirportTime = checkIn + security + boarding + gateWalk;
    airportProcessTime.value = _formatDuration(totalAirportTime);
    boardingTime.value = _formatDuration(boarding);
    homeToAirportTotal.value = _formatDuration(traffic + totalAirportTime);

    final totalBuffer =
        traffic +
        airportBuffer +
        totalAirportTime +
        uncertainty +
        terminalSwitchPenalty;
    recommendedBuffer.value = _formatDuration(totalBuffer);
    totalJourneyDuration.value = _calculateTotalJourney(
      traffic,
      totalAirportTime,
    );

    if (departure == null) {
      leaveHomeAt.value = "Not available (departure time missing)";
      timingStatus.value =
          "Flight departure time could not be read; fix API date format or pick another flight.";
      lateWarning.value = "";
      _leaveAtDateTime = null;
      _warningTimer?.cancel();
      return;
    }

    final leaveTime = departure.subtract(totalBuffer);
    _leaveAtDateTime = leaveTime;
    leaveHomeAt.value =
        "${leaveTime.year}-${leaveTime.month.toString().padLeft(2, '0')}-${leaveTime.day.toString().padLeft(2, '0')} "
        "${leaveTime.hour.toString().padLeft(2, '0')}:${leaveTime.minute.toString().padLeft(2, '0')}";
    _updateFlightTimelineStatus(departure, leaveTime);
    _startWarningClock();
  }

  bool _isSelectedDateToday() {
    final d = selectedFlightDate.value;
    final t = DateTime.now();
    return d.year == t.year && d.month == t.month && d.day == t.day;
  }

  void _updateFlightTimelineStatus(DateTime departure, DateTime leaveTime) {
    final now = DateTime.now();
    final status = (flights.first['status'] ?? '').toString();
    final tripDay = selectedFlightDateLabel.value;

    if (_isFlightDeparted(departure, status)) {
      flightMissedWarning.value =
          "Flight missed — this flight already departed at "
          "${_formatDateTimeDisplay(departure)}. You cannot catch this flight now.";
      timeUntilDeparture.value =
          "Departed ${_formatDuration(now.difference(departure))} ago";
      timeUntilLeaveHome.value = "N/A — flight already left";
      timingStatus.value = "Flight has departed. Plan a new booking or next flight.";
      lateWarning.value = "";
      _leaveAtDateTime = null;
      _warningTimer?.cancel();
      return;
    }

    flightMissedWarning.value = "";

    if (!_isSelectedDateToday()) {
      timeUntilDeparture.value =
          "Flight on $tripDay — departs ${_formatDateTimeDisplay(departure)} "
          "(in ${_formatDuration(departure.difference(now))} from now)";
      timeUntilLeaveHome.value =
          "Leave home on $tripDay at ${_formatDateTimeDisplay(leaveTime)} "
          "(in ${_formatDuration(leaveTime.difference(now))} from now)";
      timingStatus.value =
          "Upcoming trip ($tripDay) — not using today's late alert.";
      lateWarning.value = "";
      return;
    }

    if (departure.isAfter(now)) {
      timeUntilDeparture.value =
          "Departure in ${_formatDuration(departure.difference(now))}";
      if (leaveTime.isAfter(now)) {
        timeUntilLeaveHome.value =
            "Recommended leave in ${_formatDuration(leaveTime.difference(now))}";
      } else {
        timeUntilLeaveHome.value = "Leave time already passed for this plan";
      }
    } else {
      timeUntilDeparture.value = "Departure time is very soon or just passed";
      timeUntilLeaveHome.value = "";
    }
  }

  bool _isFlightDeparted(DateTime departure, String status) {
    if (!_isSelectedDateToday()) return false;

    final now = DateTime.now();
    if (departure.isAfter(now.add(const Duration(minutes: 5)))) return false;

    final s = status.toLowerCase();
    if (s == 'scheduled') {
      return departure.isBefore(now.subtract(const Duration(minutes: 20)));
    }
    if (s == 'landed' || s == 'active' || s.contains('en-route')) {
      return true;
    }
    return departure.isBefore(now.subtract(const Duration(minutes: 20)));
  }

  String _formatDateTimeDisplay(DateTime dt) {
    return "${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} "
        "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  Future<void> pickFlightDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedFlightDate.value,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      selectedFlightDate.value = DateTime(
        picked.year,
        picked.month,
        picked.day,
      );
      _refreshSelectedDateLabel();
    }
  }

  void _refreshSelectedDateLabel() {
    final d = selectedFlightDate.value;
    final today = DateTime.now();
    final isToday = d.year == today.year &&
        d.month == today.month &&
        d.day == today.day;
    final tomorrow = today.add(const Duration(days: 1));
    final isTomorrow = d.year == tomorrow.year &&
        d.month == tomorrow.month &&
        d.day == tomorrow.day;
    final dateStr =
        "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
    if (isToday) {
      selectedFlightDateLabel.value = "Today ($dateStr)";
    } else if (isTomorrow) {
      selectedFlightDateLabel.value = "Tomorrow ($dateStr)";
    } else {
      selectedFlightDateLabel.value = dateStr;
    }
  }

  String _calculateTotalJourney(Duration drive, Duration airportTime) {
    Duration total = drive + airportTime;
    for (int i = 0; i < flights.length; i++) {
      final seg = flights[i];
      final dep = _parseApiDate((seg['departure'] ?? '').toString());
      final arr = _parseApiDate((seg['arrival'] ?? '').toString());
      if (dep != null && arr != null && arr.isAfter(dep)) {
        total += arr.difference(dep);
      }
      if (i < flights.length - 1) {
        final nextDep = _parseApiDate(
          (flights[i + 1]['departure'] ?? '').toString(),
        );
        if (arr != null && nextDep != null && nextDep.isAfter(arr)) {
          total += nextDep.difference(arr);
        }
      }
    }
    return _formatDuration(total);
  }

  void _startWarningClock() {
    _warningTimer?.cancel();
    _checkLateWarning();
    _warningTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkLateWarning();
    });
  }

  void _checkLateWarning() {
    if (flightMissedWarning.value.isNotEmpty) return;
    if (_leaveAtDateTime == null) return;

    if (!_isSelectedDateToday()) {
      lateWarning.value = "";
      final remaining = _leaveAtDateTime!.difference(DateTime.now());
      if (remaining.isNegative) {
        timingStatus.value =
            "Selected trip day has passed — pick a new date or flight.";
      } else {
        timingStatus.value =
            "Trip on ${selectedFlightDateLabel.value} — leave home in "
            "${_formatDuration(remaining)} (countdown from today).";
        timeUntilLeaveHome.value =
            "Leave home in ${_formatDuration(remaining)}";
      }
      return;
    }

    final now = DateTime.now();
    if (now.isAfter(_leaveAtDateTime!)) {
      lateWarning.value =
          "Warning: You are late. Leave immediately to avoid missing boarding.";
      timingStatus.value = "Late: device time is greater than leave time.";
    } else {
      final remaining = _leaveAtDateTime!.difference(now);
      timingStatus.value =
          "On track — leave in ${_formatDuration(remaining)}.";
      lateWarning.value = "";
      if (flights.isNotEmpty) {
        final dep = _parseApiDate((flights.first['departure'] ?? '').toString());
        if (dep != null && dep.isAfter(now)) {
          timeUntilLeaveHome.value =
              "Recommended leave in ${_formatDuration(remaining)}";
        }
      }
    }
  }

  DateTime? _parseApiDate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == "n/a") return null;
    final direct = DateTime.tryParse(trimmed);
    if (direct != null) return direct.toLocal();
    final normalized = trimmed.replaceFirst(' ', 'T');
    final parsed = DateTime.tryParse(normalized);
    return parsed?.toLocal();
  }

  Duration _parseHumanDuration(String value) {
    final hourMatch = RegExp(r'(\d+)\s*h').firstMatch(value);
    final minMatch = RegExp(r'(\d+)\s*min').firstMatch(value);
    final hours = int.tryParse(hourMatch?.group(1) ?? '0') ?? 0;
    final mins = int.tryParse(minMatch?.group(1) ?? '0') ?? 0;
    return Duration(hours: hours, minutes: mins);
  }

  String _formatDuration(Duration d) {
    if (d.isNegative) return _formatDuration(d.abs());
    final days = d.inDays;
    final hours = d.inHours % 24;
    final mins = d.inMinutes % 60;
    if (days > 0) return "$days d $hours h $mins min";
    if (hours > 0) return "$hours h $mins min";
    return "$mins min";
  }

  @override
  void onInit() {
    super.onInit();
    _refreshSelectedDateLabel();
    timingStatus.value = "Generate summary to see leave-time alerts.";
  }
}
