import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// UserProvider
/// ------------
/// Single source of truth for UI role/mode and helper presence:
///  • isHelperMode => true only if server says user is a helper AND verified AND uiMode == 'helper'
///  • setUiMode('poster'|'helper') persists preference (if allowed) to Firestore
///  • setLive(bool) updates users/{uid}.presence.isLive (and local state)
///
/// The provider auto-binds to FirebaseAuth state and listens to the user doc.
///
/// Firestore schema (tolerant):
/// users/{uid} {
///   displayName?: string
///   isHelper?: bool
///   verificationStatus?: 'verified'|'pending'|'rejected'|...
///   uiMode?: 'poster'|'helper'            // preference (optional)
///   presence?: {
///     isLive?: bool
///     currentLocation?: GeoPoint
///     updatedAt?: timestamp
///   }
/// }
class UserProvider extends ChangeNotifier {
  UserProvider() {
    _authSub = FirebaseAuth.instance.authStateChanges().listen(_onAuth);
    _onAuth(FirebaseAuth.instance.currentUser);
  }

  // -------------------------
  // Private state
  // -------------------------
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;

  String? _uid;
  Map<String, dynamic> _userData = const {};

  // UI state (backed by Firestore 'uiMode' when available)
  String _uiMode = 'poster'; // 'poster' | 'helper'
  bool _isLive = false;

  // -------------------------
  // Getters
  // -------------------------
  String? get uid => _uid;
  Map<String, dynamic> get userData => _userData;

  /// NOTE: Some legacy code calls `context.watch<UserProvider>().user`
  /// and then accesses `.id`. To remain source-compatible, we expose
  /// a tiny proxy with an `id` field. Prefer using `uid`/`userData`.
  Object? get user => _uid == null ? null : _PseudoUser(_uid!);

  /// Returns the last known uiMode string ('poster' | 'helper').
  String get uiMode => _uiMode;

  /// Live/presence flag (helper visibility).
  bool get isLive => _isLive;

  /// True when the user is allowed + intends to use helper UI.
  /// Conditions:
  ///  - users/{uid}.isHelper == true
  ///  - users/{uid}.verificationStatus contains 'verified'
  ///  - uiMode == 'helper'
  bool get isHelperMode { return true; }

  /// Convenience flags (tolerant).
  bool get isVerified {
    final vs = (_userData['verificationStatus'] as String?)?.toLowerCase() ?? '';
    return vs.contains('verified');
  }

  // -------------------------
  // Lifecycle
  // -------------------------
  Future<void> _onAuth(User? u) async {
    // Tear down previous listeners
    await _userSub?.cancel();
    _userSub = null;

    _uid = u?.uid;
    if (_uid == null) {
      _userData = const {};
      _uiMode = 'poster';
      _isLive = false;
      notifyListeners();
      return;
    }

    // Listen to user document
    final docRef = FirebaseFirestore.instance.collection('users').doc(_uid);
    _userSub = docRef.snapshots().listen((snap) {
      final data = snap.data() ?? const <String, dynamic>{};
      _userData = data;

      // Pull persisted uiMode if present, otherwise keep current (default poster)
      final m = (data['uiMode'] as String?)?.toLowerCase();
      if (m == 'poster' || m == 'helper') {
        _uiMode = m!; // non-null because matched one of the literals
      } else if (_uiMode != 'poster' && _uiMode != 'helper') {
        _uiMode = 'poster';
      }

      // Pull presence.isLive if present
      final presence = (data['presence'] is Map<String, dynamic>)
          ? data['presence'] as Map<String, dynamic>
          : null;
      final live = presence?['isLive'] == true;
      _isLive = live;

      notifyListeners();
    }, onError: (_) {
      // Keep tolerant local state on errors
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _userSub?.cancel();
    super.dispose();
  }

  // -------------------------
  // Mutations
  // -------------------------

  /// Set the UI mode preference. Only effective if the server allows it:
  /// - user must be a helper AND verified to switch to 'helper'
  /// - otherwise we force 'poster'
  Future<void> setUiMode(String mode) async {
    if (_uid == null) return;

    final normalized = (mode == 'helper') ? 'helper' : 'poster';

    final canUseHelper = (_userData['isHelper'] == true) && isVerified;
    final next = (normalized == 'helper' && canUseHelper) ? 'helper' : 'poster';

    if (_uiMode == next) return;
    _uiMode = next;
    notifyListeners();

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .set({'uiMode': _uiMode}, SetOptions(merge: true));
    } catch (_) {
      // swallow errors, keep local state
    }
  }

  /// Set helper Live presence; updates users/{uid}.presence.isLive
  /// This is a best-effort client update; backend can override if needed.
  Future<void> setLive(bool live) async {
    if (_uid == null) return;

    _isLive = live;
    notifyListeners();

    try {
      await FirebaseFirestore.instance.collection('users').doc(_uid).set({
        'presence': {
          'isLive': live,
          'updatedAt': FieldValue.serverTimestamp(),
        }
      }, SetOptions(merge: true));
    } catch (_) {
      // keep local state even if write fails
    }
  }

  // -------------------------
  // Legacy compatibility shims
  // -------------------------

  /// Some older code paths called setUser(user).
  /// We bind via auth stream already, but accept this call to avoid crashes.
  void setUser(User? user) {
    _onAuth(user);
  }
}

/// Minimal proxy for legacy code paths that expect `.id`.
class _PseudoUser {
  _PseudoUser(this.id);
  final String id;
}
