import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../session/services/session_manager.dart';
import '../models/care_directory_model.dart';
import '../models/care_profile_model.dart';
import '../repositories/care_repository.dart';

enum CareLoadStatus { initial, loading, loaded, error }

class CareProvider extends ChangeNotifier {
  CareRepository _repository;
  SessionManager _sessionManager;

  CareLoadStatus _status = CareLoadStatus.initial;
  CareAccessProfile? _profile;
  CareDirectory? _familyDirectory;
  String? _errorMessage;
  Timer? _refreshTimer;
  bool _isFetching = false;
  bool _isMutating = false;

  CareProvider(this._repository, this._sessionManager);

  CareLoadStatus get status => _status;
  CareAccessProfile? get profile => _profile;
  CareDirectory? get familyDirectory => _familyDirectory;
  String? get errorMessage => _errorMessage;
  bool get isMutating => _isMutating;

  void updateDependencies(CareRepository repository, SessionManager sessionManager) {
    _repository = repository;
    _sessionManager = sessionManager;
  }

  Future<void> fetchProfile({bool silent = false}) async {
    if (_isFetching) return;
    _isFetching = true;

    final shouldShowLoading = !silent || _profile == null;
    if (shouldShowLoading) {
      _status = CareLoadStatus.loading;
      notifyListeners();
    }

    try {
      _profile = await _repository.getAccessProfile();
      final sessionUser = _sessionManager.user;
      if (sessionUser?.role == 'family' && sessionUser?.familyId != null) {
        _familyDirectory = await _repository.getFamilyDirectory(sessionUser!.familyId!);
      } else {
        _familyDirectory = null;
      }
      _errorMessage = null;
      _status = CareLoadStatus.loaded;
    } catch (_) {
      _errorMessage = '获取监护数据失败';
      if (_profile == null || !silent) {
        _status = CareLoadStatus.error;
      }
    } finally {
      _isFetching = false;
    }

    notifyListeners();
  }

  Future<bool> bindSelfDevice(
    String macAddress, {
    String? deviceName,
  }) async {
    if (_isMutating) return false;
    _isMutating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.bindSelfDevice(
        macAddress: macAddress,
        deviceName: deviceName,
      );
      await fetchProfile(silent: _profile != null);
      return true;
    } catch (error) {
      _errorMessage = _extractApiErrorMessage(error, '绑定手环失败，请稍后重试');
      return false;
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  Future<bool> unbindSelfDevice() async {
    if (_isMutating) return false;
    _isMutating = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _repository.unbindSelfDevice();
      await fetchProfile(silent: _profile != null);
      return true;
    } catch (error) {
      _errorMessage = _extractApiErrorMessage(error, '解绑设备失败，请稍后重试');
      return false;
    } finally {
      _isMutating = false;
      notifyListeners();
    }
  }

  void startAutoRefresh({Duration interval = const Duration(seconds: 3)}) {
    stopAutoRefresh();
    Future.microtask(() => fetchProfile(silent: _profile != null));
    _refreshTimer = Timer.periodic(interval, (_) {
      fetchProfile(silent: true);
    });
  }

  void stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  String _extractApiErrorMessage(Object error, String fallback) {
    if (error is DioException) {
      final responseData = error.response?.data;
      if (responseData is Map<String, dynamic>) {
        final detail = responseData['detail'];
        if (detail is String && detail.trim().isNotEmpty) {
          return _humanizeApiDetail(detail);
        }
        if (detail is Map<String, dynamic>) {
          final message = detail['message'];
          if (message is String && message.trim().isNotEmpty) {
            return _humanizeApiDetail(message);
          }
        }
      }
      final message = error.message;
      if (message != null && message.trim().isNotEmpty) {
        return message;
      }
    }
    return fallback;
  }

  String _humanizeApiDetail(String detail) {
    if (detail.contains('INVALID_MAC_ADDRESS')) {
      return '手环 MAC 地址格式不正确，请使用 AA:BB:CC:DD:EE:FF';
    }
    if (detail.contains('DEVICE_ALREADY_BOUND_TO_TARGET')) {
      return '这只手环已经绑定到当前账号';
    }
    if (detail.contains('DEVICE_ALREADY_BOUND')) {
      return '这只手环已经绑定到其他账号了';
    }
    if (detail.contains('TARGET_USER_ALREADY_HAS_DEVICE_OF_SAME_MODEL')) {
      return '当前账号已绑定同型号手环，请先解绑旧设备';
    }
    if (detail.contains('NO_BOUND_SERIAL_DEVICE')) {
      return '当前账号还没有已绑定的手环';
    }
    if (detail.contains('DEVICE_NOT_FOUND')) {
      return '未找到这只手环，请确认 MAC 地址是否正确';
    }
    return detail;
  }

  @override
  void dispose() {
    stopAutoRefresh();
    super.dispose();
  }
}
