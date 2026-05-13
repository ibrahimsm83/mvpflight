import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import '../controller/travel_controller.dart';
import '../services/api_service.dart';

class HomeScreen extends StatelessWidget {
  HomeScreen({super.key});
  final TravelController controller = Get.put(TravelController());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Flight Demo MVP"), centerTitle: true),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _placesInputCard(
                child: GooglePlaceAutoCompleteTextField(
                  textEditingController: controller.homeController,
                  googleAPIKey: ApiService.apiKey,
                  focusNode: controller.homeFocus,
                  isLatLngRequired: false,
                  inputDecoration: const InputDecoration(
                    hintText: "Enter Home Location",
                    border: InputBorder.none,
                    prefixIcon: Icon(Icons.home),
                  ),
                  itemClick: (prediction) {
                    controller.homeController.text =
                        prediction.description ?? "";
                    if (prediction.placeId != null) {
                      controller.getPlaceLatLng(prediction.placeId!);
                    }
                  },
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text(
                  "Departure airport is taken from your flight (IATA + coordinates). "
                  "You only need home + flight number.",
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller.flightController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: "Primary Flight Number",
                  hintText: "e.g. PK303 or EK611",
                ),
              ),
              const SizedBox(height: 8),
              Obx(
                () => SwitchListTile(
                  value: controller.isConnecting.value,
                  title: const Text("Connecting Flight"),
                  subtitle: const Text("Enable if journey has second segment"),
                  onChanged: (value) => controller.isConnecting.value = value,
                ),
              ),
              Obx(
                () => controller.isConnecting.value
                    ? TextField(
                        controller: controller.connectionFlightController,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: "Connecting Flight Number",
                          hintText: "e.g. EY222",
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: controller.loadTripSummary,
                  child: const Text("Generate Demo Summary"),
                ),
              ),
              const SizedBox(height: 16),
              Obx(
                () => controller.isLoading.value
                    ? const CircularProgressIndicator()
                    : Column(
                        children: [
                          _infoCard(
                            "Departure airport (from flight)",
                            controller.departureAirportLabel.value,
                          ),
                          _infoCard(
                            "Home to Airport Distance",
                            controller.distance.value,
                          ),
                          _infoCard(
                            "Drive Time (No Traffic)",
                            controller.duration.value,
                          ),
                          _infoCard(
                            "Drive Time (With Traffic)",
                            controller.traficDuration.value,
                          ),
                          _infoCard(
                            "Recommended Leave Home At",
                            controller.leaveHomeAt.value,
                          ),
                          _infoCard(
                            "Timing Status",
                            controller.timingStatus.value,
                          ),
                          _infoCard(
                            "Total Buffer Used",
                            controller.recommendedBuffer.value,
                          ),
                          _infoCard(
                            "Terminal Switch Penalty",
                            controller.terminalSwitchPenaltyText.value,
                          ),
                          _infoCard(
                            "Terminal Change Info",
                            controller.terminalChangeInfo.value,
                          ),
                          _infoCard(
                            "Airport Process Time",
                            controller.airportProcessTime.value,
                          ),
                          _infoCard(
                            "Boarding Time (inside airport)",
                            controller.boardingTime.value,
                          ),
                          _infoCard(
                            "Home to Airport Total",
                            controller.homeToAirportTotal.value,
                          ),
                          _infoCard(
                            "End-to-End Total Journey",
                            controller.totalJourneyDuration.value,
                          ),
                          _warningCard(),
                          _weatherCard(),
                          _countryWeatherCard(),
                          _flightsCard(),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placesInputCard({required Widget child}) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
  }

  Widget _infoCard(String title, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Card(
      child: ListTile(title: Text(title), subtitle: Text(value)),
    );
  }

  Widget _weatherCard() {
    return Obx(
      () => controller.flightRisk.value.isEmpty
          ? const SizedBox.shrink()
          : Card(
              color: Colors.black87,
              child: ListTile(
                title: const Text(
                  "Airport Weather",
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  "${controller.flightRisk.value}\n${controller.weatherDesc.value}",
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
    );
  }

  Widget _countryWeatherCard() {
    return Obx(() {
      if (controller.depWeather.value.isEmpty &&
          controller.arrWeather.value.isEmpty) {
        return const SizedBox.shrink();
      }
      return Card(
        child: ListTile(
          title: const Text("Weather (Both Sides)"),
          subtitle: Text(
            "${controller.depWeatherLabel.value} Weather: ${controller.depWeather.value}\n"
            "${controller.arrWeatherLabel.value} Weather: ${controller.arrWeather.value}",
          ),
        ),
      );
    });
  }

  Widget _warningCard() {
    return Obx(() {
      if (controller.lateWarning.value.isNotEmpty) {
        return Card(
          color: Colors.red.shade700,
          child: ListTile(
            leading: const Icon(
              Icons.warning_amber_rounded,
              color: Colors.white,
            ),
            title: const Text(
              "Time Alert",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              controller.lateWarning.value,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      }
      final leave = controller.leaveHomeAt.value;
      if (leave.isNotEmpty &&
          !leave.startsWith("Not available") &&
          controller.timingStatus.value.isNotEmpty &&
          !controller.timingStatus.value.contains("could not be read")) {
        return Card(
          color: Colors.green.shade800,
          child: ListTile(
            leading: const Icon(
              Icons.check_circle_outline,
              color: Colors.white,
            ),
            title: const Text(
              "Time alert",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Text(
              "${controller.timingStatus.value}\nLeave home by: $leave",
              style: const TextStyle(color: Colors.white70),
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    });
  }

  Widget _flightsCard() {
    return Obx(() {
      if (controller.flights.isEmpty) return const SizedBox.shrink();
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: controller.flights.asMap().entries.map((entry) {
              final i = entry.key + 1;
              final f = entry.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Segment $i",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text("Route: ${f['dep_iata']} -> ${f['arr_iata']}"),
                    Text("Status: ${f['status']}"),
                    Text("Departure: ${f['departure']}"),
                    Text("Arrival: ${f['arrival']}"),
                    Text("Terminal: ${f['dep_terminal']} | Gate: ${f['gate']}"),
                    Text("Delay: ${f['delay']} mins"),
                    Text("Delay Update: ${f['delay_note'] ?? 'N/A'}"),
                    Text("Data Source: ${f['provider'] ?? 'N/A'}"),
                    Text(
                      "Terminal Changed: ${f['terminal_changed'] == true ? 'Yes' : 'No'} (${f['terminal_change_source'] ?? 'derived'})",
                    ),
                    Text(
                      "Flight Duration: ${_flightDuration(f['departure'], f['arrival'])}",
                    ),
                    const Divider(),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      );
    });
  }

  String _flightDuration(dynamic dep, dynamic arr) {
    final d = DateTime.tryParse((dep ?? '').toString());
    final a = DateTime.tryParse((arr ?? '').toString());
    if (d == null || a == null || !a.isAfter(d)) return "Not available";
    final diff = a.difference(d);
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return h == 0 ? "$m min" : "$h h $m min";
  }
}
