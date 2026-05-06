import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';

class TravelController extends GetxController {
  final TextEditingController homeController = TextEditingController();
  final FocusNode homeFocus = FocusNode();
  final TextEditingController destController = TextEditingController();
  final FocusNode destFocus = FocusNode();
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
  DateTime? _leaveAtDateTime;
  Timer? _warningTimer;

  @override
  void onClose() {
    _warningTimer?.cancel();
    homeController.dispose();
    destController.dispose();
    flightController.dispose();
    connectionFlightController.dispose();
    homeFocus.dispose();
    destFocus.dispose();
    super.onClose();
  }

  Future<void> getPlaceLatLng(String placeId, {required bool isHome}) async {
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

      if (isHome) {
        homeLat.value = lat;
        homeLng.value = lng;
      } else {
        destLat.value = lat;
        destLng.value = lng;
      }
    } catch (_) {
      Get.snackbar("Location Error", "Failed to resolve selected place.");
    }
  }

  Future<void> getDistance() async {
    if (homeLat.value == 0.0 || destLat.value == 0.0) {
      throw Exception("Please select both home and airport locations.");
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

  Future<void> _analyzeSegmentWeather() async {
    if (flights.isEmpty) return;
    final first = flights.first;
    final depLat = (first['dep_lat'] ?? 0.0) as double;
    final depLng = (first['dep_lng'] ?? 0.0) as double;
    final arrLat = (first['arr_lat'] ?? 0.0) as double;
    final arrLng = (first['arr_lng'] ?? 0.0) as double;
    final depCity = (first['dep_city'] ?? '').toString();
    final arrCity = (first['arr_city'] ?? '').toString();
    depWeatherLabel.value = (first['dep_iata'] ?? 'DEP').toString();
    arrWeatherLabel.value = (first['arr_iata'] ?? 'ARR').toString();

    if (depLat != 0.0 && depLng != 0.0) {
      final depW = await ApiService.getWeather(depLat, depLng);
      depWeather.value =
          "${depW['condition']} (${depW['description']}) ${depW['temp']}C";
    } else if (depCity.isNotEmpty) {
      final depW = await ApiService.getWeatherByCity(depCity);
      depWeather.value =
          "${depW['condition']} (${depW['description']}) ${depW['temp']}C";
    } else {
      depWeather.value = "Not available";
    }

    if (arrLat != 0.0 && arrLng != 0.0) {
      final arrW = await ApiService.getWeather(arrLat, arrLng);
      arrWeather.value =
          "${arrW['condition']} (${arrW['description']}) ${arrW['temp']}C";
    } else if (arrCity.isNotEmpty) {
      final arrW = await ApiService.getWeatherByCity(arrCity);
      arrWeather.value =
          "${arrW['condition']} (${arrW['description']}) ${arrW['temp']}C";
    } else {
      arrWeather.value = "Not available";
    }
  }

  Future<void> loadTripSummary() async {
    try {
      isLoading.value = true;
      flights.clear();

      if (flightController.text.trim().isEmpty) {
        throw Exception("Please enter at least one flight number.");
      }

      await getDistance();
      await analyzeWeather();

      final firstFlight = await ApiService.getFlightData(
        flightController.text.trim(),
      );
      flights.add(firstFlight);

      if (isConnecting.value &&
          connectionFlightController.text.trim().isNotEmpty) {
        final secondFlight = await ApiService.getFlightData(
          connectionFlightController.text.trim(),
        );
        flights.add(secondFlight);
      }
      await _analyzeSegmentWeather();
      _computeLeaveHomeTime();
    } catch (e) {
      Get.snackbar("Trip Error", e.toString().replaceFirst("Exception: ", ""));
    } finally {
      isLoading.value = false;
    }
  }

  void _computeLeaveHomeTime() {
    if (traficDuration.value.isEmpty || flights.isEmpty) return;
    final depText = (flights.first['departure'] ?? '').toString();
    final DateTime? departure = _parseApiDate(depText);

    final Duration traffic = _parseHumanDuration(traficDuration.value);
    const Duration airportBuffer = Duration(hours: 3);

    final bool terminalChanged =
        (flights.first['terminal_changed'] ?? false) == true;
    final Duration terminalSwitchPenalty = terminalChanged
        ? const Duration(minutes: 30)
        : Duration.zero;

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
      timingStatus.value = "Enter a flight that has valid scheduled departure.";
      lateWarning.value = "";
      _leaveAtDateTime = null;
      return;
    }

    final leaveTime = departure.subtract(totalBuffer);
    _leaveAtDateTime = leaveTime;
    leaveHomeAt.value =
        "${leaveTime.year}-${leaveTime.month.toString().padLeft(2, '0')}-${leaveTime.day.toString().padLeft(2, '0')} "
        "${leaveTime.hour.toString().padLeft(2, '0')}:${leaveTime.minute.toString().padLeft(2, '0')}";
    _startWarningClock();
  }

  String _calculateTotalJourney(Duration drive, Duration airportTime) {
    Duration total = drive + airportTime;
    for (int i = 0; i < flights.length; i++) {
      final seg = flights[i];
      final dep = DateTime.tryParse((seg['departure'] ?? '').toString());
      final arr = DateTime.tryParse((seg['arrival'] ?? '').toString());
      if (dep != null && arr != null && arr.isAfter(dep)) {
        total += arr.difference(dep);
      }
      if (i < flights.length - 1) {
        final nextDep = DateTime.tryParse(
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
    if (_leaveAtDateTime == null) return;
    final now = DateTime.now();
    final lateThreshold = _leaveAtDateTime!.add(const Duration(minutes: 1));
    if (now.isAfter(lateThreshold)) {
      lateWarning.value =
          "Warning: You are late. Leave immediately to avoid missing boarding.";
      timingStatus.value = "Late by more than 1 minute.";
    } else {
      final remaining = _leaveAtDateTime!.difference(now);
      final mins = remaining.inMinutes;
      if (mins <= 10) {
        timingStatus.value = "Leave now. Only $mins min left.";
      } else {
        timingStatus.value = "On track. $mins min left to leave.";
      }
      lateWarning.value = "";
    }
  }

  DateTime? _parseApiDate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase() == "n/a") return null;
    final direct = DateTime.tryParse(trimmed);
    if (direct != null) return direct;
    final normalized = trimmed.replaceFirst(' ', 'T');
    return DateTime.tryParse(normalized);
  }

  Duration _parseHumanDuration(String value) {
    final hourMatch = RegExp(r'(\d+)\s*h').firstMatch(value);
    final minMatch = RegExp(r'(\d+)\s*min').firstMatch(value);
    final hours = int.tryParse(hourMatch?.group(1) ?? '0') ?? 0;
    final mins = int.tryParse(minMatch?.group(1) ?? '0') ?? 0;
    return Duration(hours: hours, minutes: mins);
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final mins = d.inMinutes % 60;
    if (hours == 0) return "$mins min";
    return "$hours h $mins min";
  }

  @override
  void onInit() {
    super.onInit();
    timingStatus.value = "Generate summary to see leave-time alerts.";
  }
}
