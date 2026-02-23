import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'services/esp32_service.dart';

void main() {
  runApp(const FacePillowApp());
}

class FacePillowApp extends StatelessWidget {
  const FacePillowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => Esp32Service(),
      child: MaterialApp(
        title: '智能人脸枕头',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
