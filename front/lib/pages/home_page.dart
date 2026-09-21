import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          '홈화면~ 아이 원 투 고 홈~',
          style: TextStyle(fontSize: 30),
        ),
      ),
    );
  }
}