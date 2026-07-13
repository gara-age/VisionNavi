import 'package:flutter/material.dart';

class TextCommandComposer extends StatelessWidget {
  const TextCommandComposer({
    super.key,
    required this.controller,
    required this.onSubmit,
    required this.isBusy,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: controller,
          minLines: 2,
          maxLines: 3,
          onSubmitted: (_) => onSubmit(),
          decoration: const InputDecoration(
            hintText: '어떤 도움이 필요한지 입력해보세요',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: isBusy ? null : onSubmit,
          child: Text(isBusy ? '처리 중' : '요청하기'),
        ),
      ],
    );
  }
}
