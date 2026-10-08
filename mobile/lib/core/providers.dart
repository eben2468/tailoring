import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/env.dart';
import 'network/api_client.dart';
import 'network/token_store.dart';

/// Root dependencies. Tests override these with fakes.
final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(baseUrl: Env.apiBaseUrl, tokens: ref.watch(tokenStoreProvider)),
);
