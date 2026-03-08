import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../models/whatsapp_analysis.dart';

const kWhatsAppServerUrl = 'http://144.126.223.193:3000';

const double kAlertThreshold  = 40.0;
const double kMediumThreshold = 55.0;
const double kHighThreshold   = 70.0;
const int    kCooldownMs      = 300000;
const int    kWindowSize      = 10;

// QR debounce: accept a new QR at most once every 30 s
const int kQrDebounceMs = 30000;

final whatsAppSocketProvider =
    ChangeNotifierProvider<WhatsAppSocketService>((ref) {
  final svc = WhatsAppSocketService();
  ref.onDispose(svc.disconnect);
  return svc;
});

// ─── Image message model ──────────────────────────────────────────────────────

class WhatsAppImageMessage {
  final String messageId;
  final String imageUrl;
  final String? senderName;
  final String? chatId;
  final DateTime timestamp;

  const WhatsAppImageMessage({
    required this.messageId,
    required this.imageUrl,
    this.senderName,
    this.chatId,
    required this.timestamp,
  });

  factory WhatsAppImageMessage.fromJson(Map<String, dynamic> j) {
    return WhatsAppImageMessage(
      messageId:  j['messageId'] as String? ?? j['id'] as String? ?? '',
      imageUrl:   j['imageUrl']  as String? ?? j['url'] as String? ??
                  j['mediaUrl']  as String? ?? '',
      senderName: j['senderName'] as String? ?? j['sender'] as String? ??
                  j['from']      as String?,
      chatId:     j['chatId'] as String?,
      timestamp:  DateTime.now(),
    );
  }
}

// ─── Service ──────────────────────────────────────────────────────────────────

class WhatsAppSocketService extends ChangeNotifier {
  io.Socket? _socket;

  String  _serverUrl  = '';
  String  _waStatus   = 'disconnected';
  String? _qrString;
  String? _qrImage;

  DateTime _lastQrAccepted = DateTime.fromMillisecondsSinceEpoch(0);

  // Once true, QR events are ignored — reset by resetSession() or disconnect
  bool _linkedOnce = false;

  List<ChatItem>  _chats      = [];
  WindowData?     _windowData;
  String?         _error;
  List<RiskAlert> _alerts     = [];
  DateTime _cooldownUntil     = DateTime.fromMillisecondsSinceEpoch(0);

  final List<WhatsAppImageMessage>                _imageMessages = [];
  final List<void Function(WhatsAppImageMessage)> _imgCallbacks  = [];

  // ── Getters ───────────────────────────────────────────────────────────────
  String  get serverUrl   => _serverUrl;
  String  get waStatus    => _waStatus;
  String? get qrString    => _qrString;
  String? get qrImage     => _qrImage;
  List<ChatItem>  get chats      => List.unmodifiable(_chats);
  WindowData?     get windowData => _windowData;
  String?         get error      => _error;
  bool get isConnected => _socket?.connected ?? false;
  bool get isReady     => _waStatus == 'ready';
  List<RiskAlert> get alerts      => List.unmodifiable(_alerts);
  bool     get isInCooldown   => DateTime.now().isBefore(_cooldownUntil);
  DateTime get cooldownUntil  => _cooldownUntil;
  List<WhatsAppImageMessage> get imageMessages =>
      List.unmodifiable(_imageMessages);

  void onImageMessage(void Function(WhatsAppImageMessage) cb) =>
      _imgCallbacks.add(cb);
  void removeImageMessageCallback(void Function(WhatsAppImageMessage) cb) =>
      _imgCallbacks.remove(cb);

  // ── Connect ───────────────────────────────────────────────────────────────
  void connect(String serverUrl) {
    if (_socket != null && _serverUrl == serverUrl) return;
    _serverUrl  = serverUrl;
    _error      = null;

    _socket?.clearListeners();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;

    _socket = io.io(
      serverUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    _socket!
      ..onConnect((_) {
        _error = null;
        notifyListeners();
      })
      ..onConnectError((e) {
        _error = 'Cannot reach server: $e';
        notifyListeners();
      })
      ..onDisconnect((_) {
        // Socket-level disconnect (network drop etc.) — don't reset _linkedOnce
        // so the UI stays on the dashboard if the socket briefly reconnects.
        _waStatus = 'disconnected';
        notifyListeners();
      })

      // ── whatsapp status ──────────────────────────────────────────────────
      ..on('whatsapp_status', (data) {
        final d      = data as Map;
        final status = d['status'] as String? ?? 'unknown';

        if (status == 'authenticated' || status == 'ready') {
          // Device successfully linked — lock out QR
          _linkedOnce = true;
          _qrString   = null;
          _qrImage    = null;
        } else if (status == 'disconnected' || status == 'auth_failure') {
          // Backend reports WhatsApp itself disconnected (user logged out
          // from phone, session expired, etc.) — full reset so QR shows again
          _resetState();
        }

        _waStatus = status;
        notifyListeners();
      })

      // ── QR code ──────────────────────────────────────────────────────────
      ..on('whatsapp_qr', (data) {
        if (_linkedOnce) return; // ignore QR once linked

        final now = DateTime.now();
        if (now.difference(_lastQrAccepted).inMilliseconds < kQrDebounceMs) {
          return; // debounce rapid re-emissions
        }

        final d = data as Map;
        _qrString       = d['qr']      as String?;
        _qrImage        = d['qrImage'] as String?;
        _waStatus       = 'qr';
        _lastQrAccepted = now;
        notifyListeners();
      })

      ..on('chat_list', (data) {
        if (data is List) {
          _chats = data
              .whereType<Map<String, dynamic>>()
              .map(ChatItem.fromJson)
              .toList();
          notifyListeners();
        }
      })

      ..on('window_update', (data) {
        if (data is Map<String, dynamic>) {
          _windowData = WindowData.fromJson(data);
          _checkAlert(_windowData!);
          notifyListeners();
        }
      })

      ..on('image_message', (data) {
        if (data is Map<String, dynamic>) _handleImagePayload(data);
      })

      ..on('message_create', _onRawMessage)
      ..on('message',        _onRawMessage)
      ..on('new_message',    _onRawMessage)
      ..on('wa_message', (data) {
        final inner = data is Map ? data['message'] ?? data : data;
        if (inner is Map<String, dynamic>) _onRawMessage(inner);
      });

    _socket!.connect();
  }

  // ── Reset session (unlink / logout) ───────────────────────────────────────
  /// Call this when the user taps "Unlink Device" in the UI.
  /// Tears down the current socket, resets all state, and reconnects so a
  /// fresh QR code is requested from the backend.
  void resetSession() {
    _resetState();
    _waStatus = 'disconnected';
    notifyListeners();

    // Fully tear down and reconnect so the backend sends a new QR
    _socket?.clearListeners();
    _socket?.disconnect();
    _socket?.dispose();
    _socket     = null;
    _serverUrl  = ''; // force connect() to re-register all listeners

    Future.delayed(const Duration(milliseconds: 500), () {
      connect(kWhatsAppServerUrl);
    });
  }

  // ── Internal state reset (does NOT touch socket) ──────────────────────────
  void _resetState() {
    _linkedOnce      = false;
    _qrString        = null;
    _qrImage         = null;
    _chats           = [];
    _windowData      = null;
    _imageMessages.clear();
    _lastQrAccepted  = DateTime.fromMillisecondsSinceEpoch(0);
  }

  // ── Raw message handler ───────────────────────────────────────────────────
  void _onRawMessage(dynamic data) {
    if (data is! Map) return;
    final d = Map<String, dynamic>.from(data as Map);

    final hasMedia = d['hasMedia'] == true ||
        d['type'] == 'image' ||
        (d['mimetype']?.toString().startsWith('image/') ?? false);
    if (!hasMedia) return;

    final imageUrl = d['imageUrl'] as String? ??
                     d['mediaUrl'] as String? ??
                     d['url']      as String? ??
                     d['body']     as String?;
    if (imageUrl == null || imageUrl.isEmpty) return;

    final rawId = d['id'];
    final msgId = (rawId is Map ? rawId['_serialized'] : null) as String? ??
                  rawId as String?                                          ??
                  d['messageId'] as String?                                 ??
                  '${DateTime.now().millisecondsSinceEpoch}';

    _handleImagePayload({
      'messageId':  msgId,
      'imageUrl':   imageUrl,
      'senderName': d['from'] as String? ?? d['senderName'] as String?,
      'chatId':     d['chatId'] as String? ?? d['from'] as String?,
    });
  }

  void _handleImagePayload(Map<String, dynamic> payload) {
    final msg = WhatsAppImageMessage.fromJson(payload);
    if (msg.messageId.isEmpty || msg.imageUrl.isEmpty) return;
    if (_imageMessages.any((m) => m.messageId == msg.messageId)) return;

    _imageMessages.insert(0, msg);
    if (_imageMessages.length > 100) {
      _imageMessages.removeRange(100, _imageMessages.length);
    }
    for (final cb in List.of(_imgCallbacks)) cb(msg);
    notifyListeners();
  }

  // ── Alert logic ───────────────────────────────────────────────────────────
  void _checkAlert(WindowData win) {
    if (win.windowRisk < kAlertThreshold) return;
    final now = DateTime.now();
    if (now.isBefore(_cooldownUntil)) return;

    final AlertLevel level;
    if (win.windowRisk >= kHighThreshold) {
      level = AlertLevel.high;
    } else if (win.windowRisk >= kMediumThreshold) {
      level = AlertLevel.medium;
    } else {
      level = AlertLevel.mild;
    }

    _alerts.insert(0, RiskAlert(
      level:           level,
      windowRisk:      win.windowRisk,
      dominantEmotion: win.dominantEmotion,
      messageCount:    win.window.length,
      timestamp:       now,
    ));
    if (_alerts.length > 20) _alerts = _alerts.sublist(0, 20);
    _cooldownUntil = now.add(const Duration(milliseconds: kCooldownMs));
  }

  void clearAlerts() {
    _alerts = [];
    notifyListeners();
  }

  void disconnect() {
    _socket?.clearListeners();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _resetState();
    _waStatus = 'disconnected';
    notifyListeners();
  }

  @override
  void dispose() {
    _socket?.clearListeners();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    super.dispose();
  }
}