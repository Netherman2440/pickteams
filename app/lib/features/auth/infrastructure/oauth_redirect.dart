import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Only the web branch may read a browser origin. Password recovery keeps its
/// separate web redirect and is not part of this native OAuth callback.
String oauthRedirect({required bool isWeb, required Uri Function() webUri}) =>
    isWeb
    ? '${webUri().origin}/#/auth/callback'
    : 'pl.pickteams://auth/callback';

final oauthRedirectProvider = Provider<String>(
  (ref) => oauthRedirect(isWeb: kIsWeb, webUri: () => Uri.base),
);
