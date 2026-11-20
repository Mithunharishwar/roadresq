// FILE: lib/core/utils/firestore_failure.dart
//
// One truthful message for a Firestore failure.
//
// WHY THIS EXISTS
// Every Firestore call site collapsed `permission-denied` into the text
// "Check Firebase Rules". That message is wrong, and it sends the reader to the
// wrong place: the rules are correct and are not what fails.
//
// The reachable login flow (`lib/pages/*_login_page.dart`) authenticates
// against the Python/Mongo backend and never creates a Firebase Auth session.
// `request.auth` is therefore null on every Firestore request, and every rule
// in `firestore.rules` starts with `isAuthenticated()`, so all of them deny it.
//
// Verified directly against the live project:
//
//   GET https://firestore.googleapis.com/v1/projects/roadresq-e4b7b/
//       databases/(default)/documents/jobs
//   -> HTTP 403
//      {"error":{"code":403,"message":"Missing or insufficient permissions.",
//                "status":"PERMISSION_DENIED"}}
//
// So no edit to `firestore.rules` can fix this. The app needs a Firebase Auth
// session, or the data has to be read from the backend API.

// FirebaseException is re-exported by firebase_auth, so cloud_firestore is
// not needed here.
import 'package:firebase_auth/firebase_auth.dart';

/// Whether the app currently holds a Firebase Auth session.
///
/// Safe to call before Firebase is initialised (returns false).
bool get hasFirebaseSession {
  try {
    return FirebaseAuth.instance.currentUser != null;
  } catch (_) {
    return false;
  }
}

/// One-line summary, for SnackBars.
String firestoreFailureSummary(Object? error, {String what = 'this data'}) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return hasFirebaseSession
            ? 'Firestore denied reading $what (rule rejected it).'
            : 'Not signed in to Firebase — Firestore denies every read. '
                'Changing firestore.rules will not help.';
      case 'failed-precondition':
        return 'Firestore needs an index for $what.';
      case 'unavailable':
        return 'Firestore unreachable. Check the connection.';
      default:
        return 'Could not read $what (${error.code}).';
    }
  }
  return 'Could not read $what.';
}

/// Full explanation, for error panels shown in the body of a screen.
String describeFirestoreFailure(Object? error, {String what = 'this data'}) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        if (hasFirebaseSession) {
          return 'Firestore denied reading $what.\n\n'
              'The app is signed in to Firebase, so a security rule rejected '
              'this specific request. Check the rule for the collection being '
              'queried.\n\n(${error.code})';
        }
        return 'Firestore denied reading $what because the app is not signed '
            'in to Firebase Auth.\n\n'
            'Login goes through the RoadResQ backend, which does not create a '
            'Firebase session. request.auth is null, so every rule beginning '
            'with isAuthenticated() rejects the request.\n\n'
            'Editing firestore.rules cannot fix this. The app needs a Firebase '
            'sign-in, or this screen must read the data from the backend API.'
            '\n\n(${error.code})';
      case 'failed-precondition':
        return 'Firestore needs a composite index for $what.\n\n'
            '${error.message ?? ''}\n\n(${error.code})';
      case 'unavailable':
        return 'Firestore is unreachable. Check the device connection.\n\n'
            '(${error.code})';
      default:
        return 'Could not read $what.\n\n'
            '${error.code}: ${error.message}\n\n(${error.code})';
    }
  }
  return 'Could not read $what.\n\n$error';
}
