// Guards the client half of the rescue lifecycle.
//
// The failure these tests lock down, reported from the field:
//
//   Failed to update status: Update failed: illegal transition
//   ARRIVED -> SERVICE_COMPLETED. From ARRIVED the next state(s) are:
//   CANCELLED, SERVICE_STARTED
//
// Every role screen decided its own "next step" with a hand-written switch, and
// the mechanic's said Reached -> Completed. The shared module now mirrors
// backend/status_machine.py, and these assertions are the contract between the
// two.

import 'package:flutter_test/flutter_test.dart';

import 'package:roadresq/core/request_status.dart';

void main() {
  group('field lifecycle', () {
    test('Reached must go through In Progress before Completed', () {
      expect(RequestStatusInfo.next('Reached'), RequestStatus.inProgress);
      expect(RequestStatusInfo.next('in_progress'), RequestStatus.completed);
      // The exact jump that failed in the field is no longer offered.
      expect(RequestStatusInfo.next('Reached')!.label, isNot('Completed'));
    });

    test('the whole field chain is the backend happy path', () {
      const chain = <String>[
        'Assigned',
        'Accepted',
        'On The Way',
        'Reached',
        'In Progress',
        'Completed',
      ];
      for (var i = 0; i < chain.length - 1; i++) {
        expect(
          RequestStatusInfo.next(chain[i])?.label,
          chain[i + 1],
          reason: '${chain[i]} must advance to ${chain[i + 1]}',
        );
      }
      expect(RequestStatusInfo.next('Completed'), isNull);
    });

    test('button labels match the step they perform', () {
      expect(RequestStatusInfo.nextActionLabel('On The Way'), 'Mark Reached');
      expect(RequestStatusInfo.nextActionLabel('Reached'), 'Start Service');
      expect(RequestStatusInfo.nextActionLabel('In Progress'), 'Complete Service');
      // Assistants pick the customer up, so their wording differs by one step.
      expect(
        RequestStatusInfo.nextActionLabel('Assigned', audience: 'assistant'),
        'Accept Pickup',
      );
    });
  });

  group('wire format', () {
    test('every step sends a token the backend accepts', () {
      expect(RequestStatusInfo.apiValue('In Progress'), 'in_progress');
      expect(RequestStatusInfo.apiValue('On The Way'), 'on_the_way');
      expect(RequestStatusInfo.apiValue('Reached'), 'reached');
      expect(RequestStatusInfo.apiValue('Completed'), 'completed');
    });

    test('canonical codes, labels and legacy spellings all parse', () {
      expect(RequestStatusInfo.parse('SERVICE_STARTED'), RequestStatus.inProgress);
      expect(RequestStatusInfo.parse('service_started'), RequestStatus.inProgress);
      expect(RequestStatusInfo.parse('In Progress'), RequestStatus.inProgress);
      expect(RequestStatusInfo.parse('in progress'), RequestStatus.inProgress);
      expect(RequestStatusInfo.parse('ARRIVED'), RequestStatus.arrived);
      expect(RequestStatusInfo.parse('reached'), RequestStatus.arrived);
      expect(RequestStatusInfo.parse('CREATED'), RequestStatus.pending);
      expect(RequestStatusInfo.parse(null), isNull);
    });

    test('unknown values pass through instead of being mislabelled', () {
      expect(RequestStatusInfo.label('Some Future State'), 'Some Future State');
      expect(RequestStatusInfo.apiValue('Some Future State'), 'some_future_state');
    });
  });

  test('a job is "active" for the whole field window, including In Progress', () {
    for (final raw in ['Accepted', 'On The Way', 'Reached', 'In Progress']) {
      expect(RequestStatusInfo.parse(raw)?.isFieldActive, isTrue, reason: raw);
    }
    for (final raw in ['Assigned', 'Completed', 'Cancelled']) {
      expect(RequestStatusInfo.parse(raw)?.isFieldActive, isFalse, reason: raw);
    }
  });
}
