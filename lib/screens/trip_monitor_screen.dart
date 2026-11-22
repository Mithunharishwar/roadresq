import 'package:material_ui/material_ui.dart';
import '../services/sensor_service.dart';
import 'diagnose_screen.dart';

class TripMonitorScreen extends StatefulWidget {
  final String userId;
  const TripMonitorScreen({super.key, required this.userId});

  @override
  State<TripMonitorScreen> createState() => _TripMonitorScreenState();
}

class _TripMonitorScreenState extends State<TripMonitorScreen> {
  final sensorService = SensorService();
  bool isMonitoring = false;
  double currentScore = 0.0;

  @override
  void initState() {
    super.initState();
    sensorService.onScoreUpdate = (score) {
      if (mounted) setState(() => currentScore = score);
    };
  }

  @override
  void dispose() {
    sensorService.stopMonitoring();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color scoreColor = currentScore > 0.8
        ? Colors.red
        : currentScore > 0.5
            ? Colors.orange
            : Colors.green;

    return Scaffold(
        appBar: AppBar(
            title: Text("Trip Monitoring"), backgroundColor: Colors.deepOrange),
        body: Center(
            child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.vibration, size: 100, color: scoreColor),
                      SizedBox(height: 30),
                      Text("Anomaly Score",
                          style: TextStyle(fontSize: 24, color: Colors.grey)),
                      Text(currentScore.toStringAsFixed(2),
                          style: TextStyle(
                              fontSize: 80,
                              fontWeight: FontWeight.bold,
                              color: scoreColor)),
                      SizedBox(height: 20),
                      Text(
                          currentScore > 0.8
                              ? "High vibration detected!"
                              : currentScore > 0.5
                                  ? "Unusual movement"
                                  : "Normal",
                          style: TextStyle(
                              fontSize: 18,
                              color: scoreColor,
                              fontWeight: FontWeight.w600)),
                      SizedBox(height: 50),
                      ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepOrange,
                              minimumSize: Size(double.infinity, 55),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15))),
                          onPressed: () {
                            setState(() => isMonitoring = !isMonitoring);
                            isMonitoring
                                ? sensorService.startMonitoring(widget.userId)
                                : sensorService.stopMonitoring();
                          },
                          child: Text(
                              isMonitoring
                                  ? "Stop Trip"
                                  : "Start Trip Monitoring",
                              style: TextStyle(
                                  fontSize: 18, color: Colors.white))),
                      SizedBox(height: 15),
                      if (currentScore > 0.8)
                        ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                minimumSize: Size(double.infinity, 50),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15))),
                            onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => DiagnoseScreen())),
                            icon: Icon(Icons.camera_alt, color: Colors.white),
                            label: Text("Diagnose Issue Now",
                                style: TextStyle(
                                    color: Colors.white, fontSize: 16)))
                    ]))));
  }
}
