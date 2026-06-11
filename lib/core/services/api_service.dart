import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/env.dart';

/// Static facade over a single Dio client.
///
/// * Tokens live in FlutterSecureStorage (Keychain on iOS / EncryptedSharedPrefs on Android).
/// * On a 401 we try /auth/refresh once with the stored refresh_token. If that
///   succeeds, the original request is replayed transparently.
class ApiService {
  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const _userIdKey = 'user_id';

  static final FlutterSecureStorage _secure = const FlutterSecureStorage();
  static String? _access;
  static String? _refresh;
  static String? _userId;
  static bool _refreshing = false;

  /// Public auth-state notifier. Fires whenever the user logs in,
  /// logs out, or has tokens cleared by the 401 interceptor (e.g.
  /// session expiry, backend secret rotation). Wire into
  /// `GoRouter.refreshListenable` so the router re-evaluates its
  /// redirect and bounces the user back to /login on expiry.
  static final ValueNotifier<bool> authState = ValueNotifier<bool>(false);

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: Env.apiUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'Content-Type': 'application/json'},
  ))
    ..interceptors.add(InterceptorsWrapper(
      onError: (e, handler) async {
        final canRetry =
            e.response?.statusCode == 401 &&
            _refresh != null &&
            !_refreshing &&
            (e.requestOptions.extra['_retried'] != true) &&
            !e.requestOptions.path.contains('/auth/refresh');

        if (!canRetry) {
          if (e.response?.statusCode == 401) {
            await clearTokens();
          }
          handler.next(e);
          return;
        }

        _refreshing = true;
        try {
          final ok = await _tryRefresh();
          if (!ok) {
            await clearTokens();
            handler.next(e);
            return;
          }
          // Replay the failed request with the new token.
          final req = e.requestOptions;
          req.extra['_retried'] = true;
          req.headers['Authorization'] = 'Bearer $_access';
          final retried = await _dio.fetch(req);
          handler.resolve(retried);
        } catch (_) {
          await clearTokens();
          handler.next(e);
        } finally {
          _refreshing = false;
        }
      },
    ));

  static Dio get dio => _dio;
  static bool get isLoggedIn => _access != null;
  static String? get currentUserId => _userId;

  /// Load any persisted tokens. Call once from main().
  static Future<void> init() async {
    _access = await _secure.read(key: _accessKey);
    _refresh = await _secure.read(key: _refreshKey);
    _userId = await _secure.read(key: _userIdKey);
    if (_access != null) {
      _dio.options.headers['Authorization'] = 'Bearer $_access';
    }
    authState.value = _access != null;
  }

  static Future<void> _saveTokens({
    required String access,
    required String refresh,
    required String userId,
  }) async {
    _access = access;
    _refresh = refresh;
    _userId = userId;
    _dio.options.headers['Authorization'] = 'Bearer $access';
    await _secure.write(key: _accessKey, value: access);
    await _secure.write(key: _refreshKey, value: refresh);
    await _secure.write(key: _userIdKey, value: userId);
    authState.value = true;
  }

  static Future<void> clearTokens() async {
    _access = null;
    _refresh = null;
    _userId = null;
    _dio.options.headers.remove('Authorization');
    await _secure.delete(key: _accessKey);
    await _secure.delete(key: _refreshKey);
    await _secure.delete(key: _userIdKey);
    // Tick the notifier so GoRouter's refreshListenable re-runs its
    // redirect and bounces the user to /login.
    authState.value = false;
  }

  static Future<bool> _tryRefresh() async {
    if (_refresh == null) return false;
    try {
      final res = await _dio.post(
        '/auth/refresh',
        data: {'refresh_token': _refresh},
        options: Options(extra: {'_retried': true}),
      );
      await _saveTokens(
        access: res.data['access_token'],
        refresh: res.data['refresh_token'],
        userId: res.data['user_id'],
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  // ── Auth ─────────────────────────────────────────────────
  static Future<Map<String, dynamic>> register({
    required String fullName, required String email,
    required String phone, required String password,
    String? dateOfBirth, String? city,
  }) async {
    final res = await _dio.post('/auth/register', data: {
      'full_name': fullName, 'email': email,
      'phone': phone, 'password': password,
      if (dateOfBirth != null) 'date_of_birth': dateOfBirth,
      if (city != null) 'city': city,
    });
    await _saveTokens(
      access: res.data['access_token'],
      refresh: res.data['refresh_token'],
      userId: res.data['user_id'],
    );
    return res.data;
  }

  static Future<Map<String, dynamic>> login({
    required String identifier, required String password,
  }) async {
    final res = await _dio.post('/auth/login',
        data: {'identifier': identifier, 'password': password});
    await _saveTokens(
      access: res.data['access_token'],
      refresh: res.data['refresh_token'],
      userId: res.data['user_id'],
    );
    return res.data;
  }

  static Future<void> logout() async => clearTokens();

  // ── Dashboard / Expenses / Savings ───────────────────────
  static Future<Map<String, dynamic>> getDashboard() async {
    final res = await _dio.get('/dashboard');
    return res.data;
  }

  static Future<Map<String, dynamic>> getExpenses({
    DateTime? from,
    DateTime? to,
    String? txnType,          // 'EXPENSE' | 'INCOME'
    String? category,         // null/'All' = no filter
    String? search,
    double? minAmount,
    double? maxAmount,
    String sort = 'recent',   // recent | oldest | high | low
  }) async {
    final q = <String, dynamic>{'sort': sort};
    if (from != null)        q['date_from']  = _toIsoDate(from);
    if (to   != null)        q['date_to']    = _toIsoDate(to);
    if (txnType != null)     q['txn_type']   = txnType;
    if (category != null && category != 'All') q['category'] = category;
    if (search != null && search.isNotEmpty)   q['search']   = search;
    if (minAmount != null)   q['min_amount'] = minAmount;
    if (maxAmount != null)   q['max_amount'] = maxAmount;
    final res = await _dio.get('/expenses', queryParameters: q);
    return Map<String, dynamic>.from(res.data as Map);
  }

  static String _toIsoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';

  static Future<Map<String, dynamic>> getExpenseTrend({int days = 30}) async {
    final res = await _dio.get('/expenses/trend',
        queryParameters: {'days': days});
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<Map<String, dynamic>> getExpenseMeta() async {
    final res = await _dio.get('/expenses/meta');
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<Map<String, dynamic>> addExpense({
    required String name,
    required String category,
    required double amount,
    String txnType = 'EXPENSE',
    String? note,
    String? paymentMethod,
    String? location,
    DateTime? txnDate,
  }) async {
    final res = await _dio.post('/expenses', data: {
      'name': name,
      'category': category,
      'amount': amount,
      'txn_type': txnType,
      if (note != null && note.isNotEmpty) 'note': note,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (location != null && location.isNotEmpty) 'location': location,
      if (txnDate != null) 'txn_date': txnDate.toUtc().toIso8601String(),
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<Map<String, dynamic>> updateExpense({
    required String id,
    String? name,
    String? category,
    double? amount,
    String? txnType,
    String? note,
    String? paymentMethod,
    String? location,
    DateTime? txnDate,
  }) async {
    final body = <String, dynamic>{};
    if (name != null)          body['name'] = name;
    if (category != null)      body['category'] = category;
    if (amount != null)        body['amount'] = amount;
    if (txnType != null)       body['txn_type'] = txnType;
    if (note != null)          body['note'] = note;
    if (paymentMethod != null) body['payment_method'] = paymentMethod;
    if (location != null)      body['location'] = location;
    if (txnDate != null)       body['txn_date'] = txnDate.toUtc().toIso8601String();
    final res = await _dio.patch('/expenses/$id', data: body);
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<void> deleteExpense(String id) async =>
      await _dio.delete('/expenses/$id');

  /// Upload a receipt image and return parsed candidate fields.
  /// Backend returns `{vendor, total, txn_date, items, confidence, raw_text}`.
  static Future<Map<String, dynamic>> ocrReceipt({
    required List<int> bytes,
    required String filename,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final res = await _dio.post(
      '/expenses/ocr', data: form,
      options: Options(headers: {'Content-Type': 'multipart/form-data'}),
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  // ── Statements inbox (works for users without email) ────
  /// Past monthly statements stored on the server, newest first.
  static Future<List<dynamic>> listStatements() async {
    final res = await _dio.get('/expenses/statements');
    return res.data as List;
  }

  /// Generates (or regenerates) a statement for a given month and dispatches
  /// notifications. Returns {id, period_label, size_bytes, channels}.
  static Future<Map<String, dynamic>> generateStatement({
    required int year, required int month,
  }) async {
    final res = await _dio.post(
      '/expenses/statements/generate',
      queryParameters: {'year': year, 'month': month},
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Download a previously persisted statement by id.
  static Future<({List<int> bytes, String filename, String mimeType})>
      downloadStatement(String id) async {
    final res = await _dio.get(
      '/expenses/statements/$id/download',
      options: Options(responseType: ResponseType.bytes),
    );
    final mime = res.headers.value('content-type') ?? 'application/pdf';
    final disp = res.headers.value('content-disposition') ?? '';
    final m = RegExp(r'filename="?([^"]+)"?').firstMatch(disp);
    final filename = m?.group(1) ?? 'statement.pdf';
    return (
      bytes: (res.data as List).cast<int>(),
      filename: filename,
      mimeType: mime,
    );
  }

  static Future<void> deleteStatement(String id) async =>
      await _dio.delete('/expenses/statements/$id');

  /// Returns ({bytes, filename, mimeType}) for a CSV/Excel/PDF statement.
  /// Use [filename] verbatim when triggering the browser download.
  static Future<({List<int> bytes, String filename, String mimeType})>
      exportExpenses({
    required String format,           // 'csv' | 'xlsx' | 'pdf'
    DateTime? from, DateTime? to,
  }) async {
    final q = <String, dynamic>{'format': format};
    if (from != null) q['date_from'] = _toIsoDate(from);
    if (to   != null) q['date_to']   = _toIsoDate(to);
    final res = await _dio.get(
      '/expenses/export',
      queryParameters: q,
      options: Options(responseType: ResponseType.bytes),
    );
    final mime = res.headers.value('content-type') ?? 'application/octet-stream';
    final disp = res.headers.value('content-disposition') ?? '';
    final m = RegExp(r'filename="?([^"]+)"?').firstMatch(disp);
    final filename = m?.group(1) ?? 'statement.$format';
    return (
      bytes: (res.data as List).cast<int>(),
      filename: filename,
      mimeType: mime,
    );
  }

  // ── Budgets ──────────────────────────────────────────────
  static Future<List<dynamic>> getBudgets() async {
    final res = await _dio.get('/budgets');
    return res.data as List;
  }

  static Future<Map<String, dynamic>> setBudget({
    required String category,
    required double amount,
    String period = 'monthly',
  }) async {
    final res = await _dio.put('/budgets', data: {
      'category': category, 'amount': amount, 'period': period,
    });
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<void> deleteBudget(String category) async =>
      await _dio.delete('/budgets/$category');

  /// Triggers an email of the user's PDF statement. Year/month default to
  /// the previous calendar month on the server. Throws on 503 when SMTP is
  /// not configured server-side.
  static Future<Map<String, dynamic>> emailMyStatement({
    int? year, int? month,
  }) async {
    final q = <String, dynamic>{};
    if (year  != null) q['year']  = year;
    if (month != null) q['month'] = month;
    final res = await _dio.post('/expenses/email-statement',
        queryParameters: q);
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<Map<String, dynamic>> getSavings() async {
    final res = await _dio.get('/savings');
    return res.data;
  }

  /// Rich dashboard payload: trend, allocation, upcoming runs, activity feed.
  /// Safe to call alongside `getSavings()` in parallel.
  static Future<Map<String, dynamic>> getSavingsInsights() async {
    final res = await _dio.get('/savings/insights');
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<Map<String, dynamic>?> createGoal({
    required String name, required String emoji,
    required double target, String? note,
    DateTime? deadline,
  }) async {
    final res = await _dio.post('/savings/goals', data: {
      'name': name, 'emoji': emoji,
      'target': target, 'note': note ?? '',
      if (deadline != null) 'deadline': deadline.toUtc().toIso8601String(),
    });
    if (res.data == null) return null;
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<Map<String, dynamic>> addFunds(String goalId, double amount) async {
    final res = await _dio.patch(
        '/savings/goals/$goalId/add-funds', data: {'amount': amount});
    return res.data;
  }

  static Future<Map<String, dynamic>> withdrawGoal(String goalId) async {
    final res = await _dio.patch('/savings/goals/$goalId/withdraw');
    return res.data;
  }

  static Future<void> deleteGoal(String goalId) async =>
      await _dio.delete('/savings/goals/$goalId');

  static Future<void> updateAutoSave({
    required int percent, required bool active, String provider = 'MTN Money',
  }) async {
    await _dio.patch('/savings/auto-save', data: {
      'percent': percent, 'active': active, 'provider': provider,
    });
  }

  // ── MoMo wallet link ─────────────────────────────────────
  /// Returns the current user's linked wallet, or null if none.
  static Future<Map<String, dynamic>?> getMoMoLink() async {
    final res = await _dio.get('/momo/link');
    if (res.data == null) return null;
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<Map<String, dynamic>> linkMoMo(String phone) async {
    final res = await _dio.post('/momo/link', data: {'phone': phone});
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<void> unlinkMoMo() async {
    await _dio.delete('/momo/link');
  }

  // ── Per-goal auto-save plans (real MoMo Collections) ─────
  /// Creates a recurring auto-save plan tied to a specific goal.
  /// Provide either `amount` (XAF) or `assumedMonthlyIncome` so the backend
  /// can compute the per-period amount.
  static Future<Map<String, dynamic>> createAutoSavePlan({
    required String goalId,
    required int percent,
    required String frequency,    // daily | weekly | monthly
    double? amount,
    double? assumedMonthlyIncome,
    bool? reminderEnabled,
  }) async {
    final res = await _dio.post(
      '/savings/goals/$goalId/auto-save',
      data: {
        'percent': percent,
        'frequency': frequency,
        if (amount != null) 'amount': amount,
        if (assumedMonthlyIncome != null)
          'assumed_monthly_income': assumedMonthlyIncome,
        if (reminderEnabled != null) 'reminder_enabled': reminderEnabled,
      },
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<Map<String, dynamic>?> getAutoSavePlan(String goalId) async {
    try {
      final res = await _dio.get('/savings/goals/$goalId/auto-save');
      return Map<String, dynamic>.from(res.data as Map);
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> updateAutoSavePlan({
    required String goalId,
    int? percent,
    String? frequency,
    double? amount,
    bool? active,
    bool? reminderEnabled,
  }) async {
    final body = <String, dynamic>{};
    if (percent         != null) body['percent']          = percent;
    if (frequency       != null) body['frequency']        = frequency;
    if (amount          != null) body['amount']           = amount;
    if (active          != null) body['active']           = active;
    if (reminderEnabled != null) body['reminder_enabled'] = reminderEnabled;
    final res = await _dio.patch(
      '/savings/goals/$goalId/auto-save', data: body,
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<void> deleteAutoSavePlan(String goalId) async {
    await _dio.delete('/savings/goals/$goalId/auto-save');
  }

  // ── Njangi ───────────────────────────────────────────────
  static Future<Map<String, dynamic>> getNjangi() async {
    final res = await _dio.get('/njangi');
    return res.data;
  }

  static Future<Map<String, dynamic>> createNjangiGroup({
    required String name, required double contribution,
    required String frequency, required int maxMembers,
    String? description, String? startDate,
  }) async {
    final res = await _dio.post('/njangi/groups', data: {
      'name': name, 'contribution': contribution,
      'frequency': frequency, 'max_members': maxMembers,
      if (description != null) 'description': description,
      if (startDate != null) 'start_date': startDate,
    });
    return res.data;
  }

  static Future<Map<String, dynamic>> previewGroup(String inviteCode) async {
    final res = await _dio.get('/njangi/groups/preview/$inviteCode');
    return res.data;
  }

  static Future<Map<String, dynamic>> joinNjangiGroup(String inviteCode) async {
    final res = await _dio.post('/njangi/groups/join',
        data: {'invite_code': inviteCode});
    return res.data;
  }

  static Future<Map<String, dynamic>> contributeNjangi(String groupId) async {
    final res = await _dio.post('/njangi/groups/$groupId/contribute');
    return res.data;
  }

  static Future<Map<String, dynamic>> activateNjangiGroup(String groupId) async {
    final res = await _dio.post('/njangi/groups/$groupId/activate');
    return res.data;
  }

  static Future<Map<String, dynamic>> updateMaxMembers(
      String groupId, int maxMembers) async {
    final res = await _dio.patch(
        '/njangi/groups/$groupId/max-members',
        data: {'max_members': maxMembers});
    return res.data;
  }

  /// Rename / edit description. Pass only the fields you want to change.
  static Future<Map<String, dynamic>> updateNjangiGroup(
      String groupId, {String? name, String? description}) async {
    final body = <String, dynamic>{};
    if (name != null)        body['name'] = name;
    if (description != null) body['description'] = description;
    final res = await _dio.patch('/njangi/groups/$groupId', data: body);
    return res.data;
  }

  /// Flip an active group to paused, or a paused group back to active.
  static Future<Map<String, dynamic>> togglePauseNjangiGroup(
      String groupId) async {
    final res = await _dio.post('/njangi/groups/$groupId/pause');
    return res.data;
  }

  /// Admin-only: delete the group (cascades to members + contributions).
  static Future<Map<String, dynamic>> deleteNjangiGroup(String groupId) async {
    final res = await _dio.delete('/njangi/groups/$groupId');
    return res.data;
  }

  /// Non-admin: leave the group. Refused if you've already paid this cycle.
  static Future<Map<String, dynamic>> leaveNjangiGroup(String groupId) async {
    final res = await _dio.post('/njangi/groups/$groupId/leave');
    return res.data;
  }

  /// Unified payment history for a group — contributions + payouts,
  /// newest first. Each event includes `type`, actor name, cycle, and
  /// amount (plus payout-specific gross/escrow/trust fields).
  static Future<List<Map<String, dynamic>>> getNjangiHistory(
      String groupId) async {
    final res = await _dio.get('/njangi/groups/$groupId/history');
    final list = (res.data['events'] as List?) ?? const [];
    return list.cast<Map<String, dynamic>>();
  }

  // ── Njangi group chat ────────────────────────────────────
  /// Fetch a page of group messages, oldest → newest.
  /// Pass [before] (ISO timestamp) to page backwards into older history.
  static Future<List<Map<String, dynamic>>> getGroupMessages(
      String groupId, {String? before, int limit = 50}) async {
    final res = await _dio.get(
      '/njangi/groups/$groupId/messages',
      queryParameters: {
        if (before != null) 'before': before,
        'limit': limit,
      },
    );
    final list = (res.data['messages'] as List?) ?? const [];
    return list.cast<Map<String, dynamic>>();
  }

  /// REST fallback for sending — used when the WS isn't connected.
  static Future<Map<String, dynamic>> sendGroupMessage(
      String groupId, String content) async {
    final res = await _dio.post(
      '/njangi/groups/$groupId/messages',
      data: {'content': content},
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Build the WebSocket URL for a group's chat. Returns `null` if the
  /// caller isn't authenticated. The current access token is appended
  /// as `?token=` because browser WebSockets can't send headers.
  static String? groupChatWsUrl(String groupId) {
    if (_access == null) return null;
    final origin = Env.apiBaseUrl;
    final wsOrigin = origin.startsWith('https://')
        ? origin.replaceFirst('https://', 'wss://')
        : origin.replaceFirst('http://', 'ws://');
    return '$wsOrigin${Env.apiPrefix}/njangi/groups/$groupId/chat'
        '?token=${Uri.encodeComponent(_access!)}';
  }

  // ── Profile ──────────────────────────────────────────────
  static Future<Map<String, dynamic>> getMyProfile() async {
    final res = await _dio.get('/profile/me');
    return res.data;
  }

  static Future<Map<String, dynamic>> getUserProfile(String userId) async {
    final res = await _dio.get('/profile/$userId');
    return res.data;
  }

  static Future<Map<String, dynamic>> updateProfile({
    String? fullName, String? phone, String? bio,
    String? location, String? occupation,
    String? incomeBracket, String? preferredLanguage,
  }) async {
    final data = <String, dynamic>{};
    if (fullName          != null) data['full_name']          = fullName;
    if (phone             != null) data['phone']              = phone;
    if (bio               != null) data['bio']                = bio;
    if (location          != null) data['location']           = location;
    if (occupation        != null) data['occupation']         = occupation;
    if (incomeBracket     != null) data['income_bracket']     = incomeBracket;
    if (preferredLanguage != null) data['preferred_language'] = preferredLanguage;
    final res = await _dio.patch('/profile/me', data: data);
    return res.data;
  }

  static Future<Map<String, dynamic>> uploadProfilePicture(
      List<int> bytes, String filename) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final res = await _dio.post('/profile/me/picture', data: form,
        options: Options(headers: {'Content-Type': 'multipart/form-data'}));
    return res.data;
  }

  static String pictureUrl(String? path) {
    if (path == null || path.isEmpty) return '';
    if (path.startsWith('http')) return path;
    return '${Env.assetOrigin}$path';
  }

  // ── Reminders ────────────────────────────────────────────
  static Future<Map<String, dynamic>> triggerReminders() async {
    final res = await _dio.post('/reminders/trigger');
    return res.data;
  }

  static Future<List<dynamic>> getGroupReminders(String groupId) async {
    final res = await _dio.get('/reminders/group/$groupId');
    return res.data as List;
  }

  static Future<List<dynamic>> getMyReminders() async {
    final res = await _dio.get('/reminders/me');
    return res.data as List;
  }

  // ── Notifications ────────────────────────────────────────
  static Future<void> registerPushToken({
    required String token,
    required String platform,
    String? deviceId,
  }) async {
    await _dio.post('/notifications/tokens', data: {
      'token': token,
      'platform': platform,
      if (deviceId != null) 'device_id': deviceId,
    });
  }

  static Future<void> unregisterPushToken(String token) async {
    await _dio.delete('/notifications/tokens',
        queryParameters: {'token': token});
  }

  static Future<List<dynamic>> getNotifications({int limit = 50}) async {
    final res = await _dio.get('/notifications',
        queryParameters: {'limit': limit});
    return res.data as List;
  }

  static Future<void> markNotificationRead(String id) async {
    await _dio.post('/notifications/$id/read');
  }

  static Future<void> markAllNotificationsRead() async {
    await _dio.post('/notifications/read-all');
  }

  static Future<void> deleteNotification(String id) async {
    await _dio.delete('/notifications/$id');
  }

  // ── KYC / identity verification ──────────────────────────
  /// Latest submission state for the current user. Returns
  /// `{status: 'unsubmitted' | 'pending' | 'approved' | 'rejected', ...}`.
  static Future<Map<String, dynamic>> getMyKycStatus() async {
    final res = await _dio.get('/kyc/me');
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Upload CNI front, CNI back, and a selfie. Each `bytes`/`filename` pair
  /// goes up as multipart. Returns the new submission's status payload.
  static Future<Map<String, dynamic>> submitKyc({
    required String cniNumber,
    required List<int> frontBytes, required String frontFilename,
    required List<int> backBytes,  required String backFilename,
    required List<int> selfieBytes, required String selfieFilename,
  }) async {
    final form = FormData.fromMap({
      'cni_number': cniNumber,
      'cni_front': MultipartFile.fromBytes(frontBytes, filename: frontFilename),
      'cni_back':  MultipartFile.fromBytes(backBytes,  filename: backFilename),
      'selfie':    MultipartFile.fromBytes(selfieBytes, filename: selfieFilename),
    });
    final res = await _dio.post(
      '/kyc/submit', data: form,
      options: Options(headers: {'Content-Type': 'multipart/form-data'}),
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  // ── KYC admin (reviewer-only) ────────────────────────────
  /// Reviewer queue. Defaults to PENDING; pass `status` to inspect
  /// approved or rejected history. 403 if the caller isn't a reviewer.
  static Future<List<Map<String, dynamic>>> listKycPending({String? status}) async {
    final res = await _dio.get(
      '/kyc/admin/pending',
      queryParameters: {if (status != null) 'status': status},
    );
    final list = (res.data['items'] as List?) ?? const [];
    return list.cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> approveKyc(
      String verificationId, {String? notes}) async {
    final res = await _dio.post(
      '/kyc/admin/$verificationId/approve',
      data: {if (notes != null && notes.isNotEmpty) 'notes': notes},
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  static Future<Map<String, dynamic>> rejectKyc(
      String verificationId, {String? notes}) async {
    final res = await _dio.post(
      '/kyc/admin/$verificationId/reject',
      data: {if (notes != null && notes.isNotEmpty) 'notes': notes},
    );
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Absolute URL for a KYC document. The path comes back from
  /// `listKycPending` as a relative `/api/v1/kyc/admin/...` route;
  /// prepend the API origin so `Image.network` can fetch it.
  static String kycDocUrl(String relativePath) {
    if (relativePath.startsWith('http')) return relativePath;
    return '${Env.apiBaseUrl}$relativePath';
  }
}
