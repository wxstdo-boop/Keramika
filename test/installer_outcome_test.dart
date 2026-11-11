import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keramika/services/installer.dart';

/// Итог самообновления приходит из натива двумя путями: push-вызовом
/// `onInstallResult` и pull-методом `consumeInstallResult` (после подмены
/// процесса). Здесь проверяем оба и их слияние в один поток.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.wetcorp.agysha/updater');

  setUp(() {
    Installer.resetForTesting();
    Installer.debugForceSupported = true;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    Installer.resetForTesting();
  });

  test('статусы PackageInstaller раскладываются по смыслу', () {
    expect(const InstallOutcome(status: 0).isSuccess, isTrue);
    expect(const InstallOutcome(status: 0).isFailure, isFalse);

    // 2 = STATUS_FAILURE_BLOCKED — система (Play Protect) отказала.
    expect(const InstallOutcome(status: 2).isBlocked, isTrue);
    expect(const InstallOutcome(status: 2).isFailure, isTrue);

    // 3 = STATUS_FAILURE_ABORTED — пользователь передумал, это не ошибка.
    expect(const InstallOutcome(status: 3).isAborted, isTrue);
    expect(const InstallOutcome(status: 3).isFailure, isFalse);

    // Прочие провалы (например, 5 = CONFLICT) — ошибка.
    expect(const InstallOutcome(status: 5).isFailure, isTrue);
  });

  test('push: onInstallResult из натива доходит до потока', () async {
    Installer.listen();
    final received = <InstallOutcome>[];
    final sub = Installer.outcomes.listen(received.add);

    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            const MethodCall('onInstallResult', <String, dynamic>{
              'status': 0,
              'message': null,
            }),
          ),
          (_) {},
        );
    await Future<void>.delayed(Duration.zero);

    expect(received, hasLength(1));
    expect(received.single.isSuccess, isTrue);

    await sub.cancel();
  });

  test('pull: придержанный результат забирается consumeInstallResult', () async {
    var consumeCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'consumeInstallResult') {
            consumeCalls++;
            return <String, dynamic>{'status': 2, 'message': 'blocked'};
          }
          return null;
        });

    final received = <InstallOutcome>[];
    final sub = Installer.outcomes.listen(received.add);

    Installer.listen();
    await Future<void>.delayed(Duration.zero);

    expect(consumeCalls, 1);
    expect(received, hasLength(1));
    expect(received.single.isBlocked, isTrue);
    expect(received.single.message, 'blocked');

    await sub.cancel();
  });

  test('listen идемпотентен: повторный вызов не плодит подписок', () async {
    var consumeCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'consumeInstallResult') {
            consumeCalls++;
            return null;
          }
          return null;
        });

    Installer.listen();
    Installer.listen();
    await Future<void>.delayed(Duration.zero);

    expect(consumeCalls, 1);
  });

  test('пустой ответ натива не рождает ложный итог', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    final received = <InstallOutcome>[];
    final sub = Installer.outcomes.listen(received.add);

    Installer.listen();
    await Future<void>.delayed(Duration.zero);

    expect(received, isEmpty);
    await sub.cancel();
  });
}
