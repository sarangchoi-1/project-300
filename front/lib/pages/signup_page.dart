import 'package:flutter/material.dart';

import 'home_page.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final TextEditingController idController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
  final TextEditingController firstNameController = TextEditingController();

  String? selectedYear;
  String? selectedMonth;
  String? selectedDay;

  bool get isPasswordMatch =>
      passwordController.text == confirmPasswordController.text;

  @override
  Widget build(BuildContext context) {
    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: const Color.fromARGB(255, 218, 216, 216),
      contentPadding: EdgeInsets.symmetric(horizontal: 13, vertical: 10),
    );

    final years = List.generate(100, (index) => (2026 - index).toString());
    final months = List.generate(12, (index) => (index + 1).toString());
    final days = List.generate(31, (index) => (index + 1).toString());

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              const SizedBox(height: 30),

              // 로고
              Center(
                child: Container(
                  width: 120,
                  height: 60,
                  color: Colors.grey.shade300,
                  alignment: Alignment.center,
                  child: const Text(
                    '앱 로고',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              const SizedBox(height: 30),

              // 아이디
              const Text('아이디*'),

              const SizedBox(height: 5),

              TextField(controller: idController, decoration: inputDecoration),

              const SizedBox(height: 15),

              // 비밀번호
              const Text('비밀번호*'),

              const SizedBox(height: 5),

              TextField(
                controller: passwordController,
                obscureText: true,
                onChanged: (_) {
                  setState(() {});
                },
                decoration: inputDecoration,
              ),

              const SizedBox(height: 15),

              // 비밀번호 확인
              const Text('비밀번호 확인*'),

              const SizedBox(height: 5),

              TextField(
                controller: confirmPasswordController,
                obscureText: true,
                onChanged: (_) {
                  setState(() {});
                },
                decoration: inputDecoration,
              ),

              const SizedBox(height: 5),

              if (confirmPasswordController.text.isNotEmpty)
                Text(
                  isPasswordMatch ? '비밀번호가 일치합니다.' : '비밀번호가 일치하지 않습니다.',
                  style: TextStyle(
                    color: isPasswordMatch ? Colors.green : Colors.red,
                  ),
                ),

              const SizedBox(height: 15),

              // 성 + 이름
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('성*'),
                        const SizedBox(height: 5),
                        TextField(
                          controller: lastNameController,
                          decoration: inputDecoration,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 15),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('이름*'),
                        const SizedBox(height: 5),
                        TextField(
                          controller: firstNameController,
                          decoration: inputDecoration,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 15),

              // 생년월일
              const Text('생년월일*'),

              const SizedBox(height: 5),

              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          builder: (context) {
                            return ListView(
                              children: years.map((year) {
                                return ListTile(
                                  title: Text(year),
                                  onTap: () {
                                    setState(() {
                                      selectedYear = year;
                                    });

                                    Navigator.pop(context);
                                  },
                                );
                              }).toList(),
                            );
                          },
                        );
                      },

                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color.fromARGB(255, 217, 216, 216),
                          borderRadius: BorderRadius.circular(16)
                        ),

                        child: Center(child: Text(selectedYear ?? '년도')),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    child: DropdownButtonFormField<String>(
                      icon: const Icon(Icons.keyboard_arrow_down),
                      initialValue: selectedMonth,
                      hint: const Text('월'),
                      items: months.map((month) {
                        return DropdownMenuItem(
                          value: month,
                          child: Text(month),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedMonth = value;
                        });
                      },
                    ),
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    child: DropdownButtonFormField<String>(
                      icon: const Icon(Icons.keyboard_arrow_down),
                      initialValue: selectedDay,
                      hint: const Text('일'),
                      items: days.map((day) {
                        return DropdownMenuItem(value: day, child: Text(day));
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          selectedDay = value;
                        });
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // 회원가입 버튼
              SizedBox(
                width: double.infinity,
                height: 50,

                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 219, 217, 217),
                  ),
                  onPressed: () {
                    if (!isPasswordMatch) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: Color.fromARGB(255, 52, 53, 72),
                          content: Text('비밀번호가 일치하지 않습니다.'),
                        ),
                      );
                      return;
                    }

                    Navigator.pushReplacement(
                      context,

                      MaterialPageRoute(builder: (context) => const HomePage()),
                    );
                  },

                  child: const Text('회원가입'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
