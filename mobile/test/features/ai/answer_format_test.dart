import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutofe/features/ai/presentation/ai_screen.dart';

void main() {
  String plain(TextSpan s) => s.toPlainText();
  List<String> bold(TextSpan s) => [for (final c in s.children!.cast<TextSpan>()) if (c.style?.fontWeight == FontWeight.w700) c.text!];

  test('bold and bullets from the model are shown as formatting, not symbols', () {
    final s = answerSpans('Start **#027 (Kaftan)** first.\n* #022: 1 h left\n- #029: due Sun', const TextStyle());
    expect(plain(s), 'Start #027 (Kaftan) first.\n• #022: 1 h left\n• #029: due Sun');
    expect(bold(s), ['#027 (Kaftan)']);
  });

  test('plain answers and stray asterisks are left readable', () {
    expect(plain(answerSpans('Work in this order:\n• #027 Kaftan', const TextStyle())), 'Work in this order:\n• #027 Kaftan');
    final odd = answerSpans('Price is **not tracked', const TextStyle());
    expect(plain(odd), 'Price is not tracked');
    expect(bold(odd), isEmpty, reason: 'an unmatched ** does not bold the rest');
  });
}
