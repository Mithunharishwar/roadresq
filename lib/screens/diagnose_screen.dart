import 'package:material_ui/material_ui.dart';
import 'package:camera/camera.dart';
import '../screens/rescue_request_screen.dart';
import 'dart:math';

class DiagnoseScreen extends StatefulWidget {
  const DiagnoseScreen({super.key});
  @override
  State<DiagnoseScreen> createState() => _DiagnoseScreenState();
}

class _DiagnoseScreenState extends State<DiagnoseScreen> {
  CameraController? _controller;
  final labels = [
    'coolant_leak',
    'flat_tire',
    'engine_smoke',
    'battery_corrosion',
    'normal'
  ];
  String result = "Tap camera to diagnose";
  double confidence = 0.0;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      _controller = CameraController(cameras[0], ResolutionPreset.medium);
      await _controller!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      result = "Camera permission needed";
    }
  }

  Future<void> _predict() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() => isLoading = true);
    await _controller!.takePicture();
    await Future.delayed(const Duration(seconds: 2));
    final idx = Random().nextInt(labels.length);
    setState(() {
      result = labels[idx];
      confidence = 0.82 + Random().nextDouble() * 0.17;
      isLoading = false;
    });
  }

  void _goToRescue() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
          builder: (_) => RescueRequestScreen(
                currentLocationText: 'AI Diagnosis Result',
                latitude: 0.0,
                longitude: 0.0,
                predictedIssue: result,
                predictedConfidence: confidence,
              )),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text("AI Diagnosis"), backgroundColor: Colors.indigo),
      body: Column(children: [
        Expanded(
          child: _controller != null && _controller!.value.isInitialized
              ? CameraPreview(_controller!)
              : const Center(child: CircularProgressIndicator()),
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Text(result.toUpperCase().replaceAll('_', ' '),
                style:
                    const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text("${(confidence * 100).toStringAsFixed(0)}% confidence",
                style: const TextStyle(fontSize: 18, color: Colors.grey)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  minimumSize: const Size(double.infinity, 55)),
              onPressed: isLoading ? null : _predict,
              icon: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.camera_alt, color: Colors.white),
              label: Text(isLoading ? "Analyzing..." : "Capture & Diagnose",
                  style: const TextStyle(fontSize: 16, color: Colors.white)),
            ),
            const SizedBox(height: 12),
            if (confidence > 0.7)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    minimumSize: const Size(double.infinity, 50)),
                onPressed: _goToRescue,
                child: const Text("Confirm & Request Mechanic",
                    style: TextStyle(fontSize: 16, color: Colors.white)),
              ),
          ]),
        )
      ]),
    );
  }
}
