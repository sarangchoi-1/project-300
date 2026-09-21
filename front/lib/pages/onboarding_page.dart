import 'package:flutter/material.dart';
import 'package:project_300/pages/signup_page.dart';
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
              WelcomePage(),
              FeaturePage(
                title: 'FEATURE DESCRIPTION 1!',
                description: 'amazing~!! \nWoW~~ \nRulu Rala~~!!!',
              ),
              FeaturePage(
                title: 'FEATURE DESCRIPTION 2!!',
                description: 'very nice! \ngamazagadoei~~ \nHi potatoes~',
              ),
              StartPage(),
            ],
          ),

          Positioned(
            bottom: 50,
            left: 40,
            right: 40,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromARGB(255, 191, 190, 190),
                foregroundColor: const Color.fromARGB(255, 40, 39, 39),
                minimumSize: const Size(0, 47),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16))
                ),
              onPressed: () {
                if (currentPage < 3) {
                  _controller.nextPage(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                } else {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SignupPage(),
                    ),
                  );
                }
              },
              child: Text(
                currentPage == 3 ? '회원가입' : '다음',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FeaturePage extends StatelessWidget {
  final String title;
  final String description;

  const FeaturePage({
    super.key,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color.fromARGB(255, 227, 227, 227),
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

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color.fromARGB(255, 227, 227, 227),
      child: const Center(
        child: Text(
          '환영합니다!',
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

class StartPage extends StatelessWidget {
  const StartPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Color.fromARGB(255, 227, 227, 227),
      child: const Center(
        child: Text(
          '시작해볼텨~?!',
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

