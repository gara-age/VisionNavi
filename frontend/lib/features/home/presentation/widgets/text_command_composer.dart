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
          minLines: 3,
          maxLines: 4,
          onSubmitted: (_) => onSubmit(),
          decoration: const InputDecoration(
            hintText: 'Type a command for search, Notepad, or dark mode.',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: isBusy ? null : onSubmit,
          child: Text(isBusy ? 'Preparing...' : 'Run Command'),
        ),
      ],
    );
  }
}
