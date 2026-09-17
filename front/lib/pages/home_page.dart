import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          '메인 화면',
          style: TextStyle(fontSize: 30),
        ),
      ),
    );
  }
}