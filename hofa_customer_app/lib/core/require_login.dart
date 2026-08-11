import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Đã đăng nhập thì trả về true ngay. Chưa thì hiện popup "Đăng nhập để tiếp tục" — bấm "Đăng
/// nhập" thì điều hướng sang /login (login_screen.dart luôn về '/' sau khi xong, không tự quay
/// lại đúng chỗ cũ — nên không cố "làm tiếp" hành động cũ ở đây, khách tự bấm lại sau khi đăng
/// nhập xong), bấm "Để sau" thì chỉ tắt popup. Cả 2 trường hợp chưa đăng nhập đều trả về false
/// — nơi gọi PHẢI kiểm tra kết quả trước khi điều hướng/thực hiện hành động.
Future<bool> requireLogin(BuildContext context) async {
  if (Supabase.instance.client.auth.currentSession != null) return true;

  final choice = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Đăng nhập để tiếp tục'),
      content: const Text('Bạn cần đăng nhập để dùng tính năng này.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Để sau'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Đăng nhập'),
        ),
      ],
    ),
  );
  if (choice == true && context.mounted) context.push('/login');
  return false;
}
