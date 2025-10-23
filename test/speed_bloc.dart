import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:speedguard/Bloc/SpeedLimitBloc/SpeedLimitBloc.dart';

class MockVibration {}
class MockAudioPlayer {}

void main() {
  group('SpeedLimitBloc', () {
    late SpeedLimitBloc bloc;

    setUp(() {
      bloc = SpeedLimitBloc();
    });

    tearDown(() {
      bloc.close();
    });

    test('initial state is SpeedLimitInitial', () {
      expect(bloc.state, SpeedLimitInitial());
    });

    blocTest<SpeedLimitBloc, SpeedLimitState>(
      'updates speed limit correctly',
      build: () => bloc,
      act: (bloc) => bloc.add(UpdateSpeedLimit(80)),
      expect: () => [
        SpeedLimitUpdated(80),
      ],
    );

    blocTest<SpeedLimitBloc, SpeedLimitState>(
      'triggers SpeedAlert when speed exceeds limit',
      build: () => bloc..emit(SpeedLimitUpdated(50)),
      act: (bloc) => bloc.add(CheckSpeed(60)),
      expect: () => [
        SpeedAlert(60),
        SpeedLimitUpdated(50), // stays at old limit
      ],
    );

    blocTest<SpeedLimitBloc, SpeedLimitState>(
      'does nothing if speed below limit',
      build: () => bloc..emit(SpeedLimitUpdated(50)),
      act: (bloc) => bloc.add(CheckSpeed(40)),
      expect: () => [],
    );
  });
}
