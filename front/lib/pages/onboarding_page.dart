import 'package:flutter/material.dart';
import 'login_page.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _controller = PageController();

  int currentPage = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          PageView(
            controller: _controller,
            onPageChanged: (index) {
              setState(() {
                currentPage = index;
              });
            },
            children: const [
              IntroScreen(
                title: '환영합니다!',
                description: '청년부 앱에 오신 것을 환영합니다.',
              ),
              IntroScreen(
                title: '출석 기능',
                description: '간편하게 출석을 체크할 수 있습니다.',
              ),
              IntroScreen(
                title: '기도 제목',
                description: '조별로 기도 제목을 나눌 수 있습니다.',
              ),
            ],
          ),

          Positioned(
            bottom: 50,
            left: 40,
            right: 40,
            child: ElevatedButton(
              onPressed: () {
                if (currentPage < 2) {
                  _controller.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                } else {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LoginPage(),
                    ),
                  );
                }
              },
              child: Text(
                currentPage == 2 ? '시작하기' : '다음',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class IntroScreen extends StatelessWidget {
  final String title;
  final String description;

  const IntroScreen({
    super.key,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFD9D9D9),
      padding: const EdgeInsets.all(32),

      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 20),

          Text(
            description,
            style: const TextStyle(
              fontSize: 15,
            ),
          ),

          const SizedBox(height: 120),
        ],
      ),
    );
  }
}