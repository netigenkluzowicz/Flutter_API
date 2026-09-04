import 'dart:async';

import 'package:flutter_api/src/single_flight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('overlapping calls share one execution', () async {
    final flight = SingleFlight<int>();
    final completer = Completer<int>();
    var starts = 0;

    Future<int> operation() {
      starts++;
      return completer.future;
    }

    final first = flight.run(operation);
    final second = flight.run(operation);
    completer.complete(7);

    expect(starts, 1);
    expect(await first, 7);
    expect(await second, 7);
  });

  test('a third overlapping call joins the same execution', () async {
    final flight = SingleFlight<int>();
    final completer = Completer<int>();
    var starts = 0;

    Future<int> operation() {
      starts++;
      return completer.future;
    }

    final first = flight.run(operation);
    final second = flight.run(operation);
    final third = flight.run(operation);
    completer.complete(1);

    expect(starts, 1);
    expect(await Future.wait([first, second, third]), [1, 1, 1]);
  });

  test('a sequential call starts a new execution', () async {
    final flight = SingleFlight<int>();
    var starts = 0;

    Future<int> operation() async {
      starts++;
      return starts;
    }

    expect(await flight.run(operation), 1);
    expect(await flight.run(operation), 2);
    expect(starts, 2);
  });

  test('a failed execution is not cached', () async {
    final flight = SingleFlight<int>();
    var starts = 0;

    Future<int> operation() async {
      starts++;
      if (starts == 1) throw StateError('network');
      return starts;
    }

    await expectLater(flight.run(operation), throwsStateError);
    expect(await flight.run(operation), 2);
  });
}
