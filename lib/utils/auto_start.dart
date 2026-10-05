import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// desktop auto-start on system boot via the per-user registry Run key
/// (Windows only; other platforms report unsupported).
/// Hand-rolled advapi32 bindings to stay independent of the win32 package
/// version's registry API surface.
abstract final class AutoStart {
  static bool get isSupported => Platform.isWindows;

  static const int _hkeyCurrentUser = 0x80000001;
  static const int _keyRead = 0x20019;
  static const int _keySetValue = 0x0002;
  static const int _regSz = 1;
  static const int _regOptionNonVolatile = 0;
  static const int _errorSuccess = 0;
  static const String _subKey =
      'Software\\Microsoft\\Windows\\CurrentVersion\\Run';
  static const String _valueName = 'PiliPlus Next';

  static bool get enabled => AutoStartOps.enabled;

  static bool setEnabled(bool enable) => AutoStartOps.setEnabled(enable);

  static Pointer<Uint16> _toUtf16(String s) {
    final units = s.codeUnits;
    final ptr = calloc<Uint16>(units.length + 1);
    for (var i = 0; i < units.length; i++) {
      ptr[i] = units[i];
    }
    ptr[units.length] = 0;
    return ptr;
  }

}

typedef _RegOpenKeyExWNative =
    Int32 Function(IntPtr, Pointer<Uint16>, Uint32, Uint32, Pointer<IntPtr>);
typedef _RegOpenKeyExWDart =
    int Function(int, Pointer<Uint16>, int, int, Pointer<IntPtr>);
typedef _RegCreateKeyExWNative =
    Int32 Function(
      IntPtr,
      Pointer<Uint16>,
      Uint32,
      Pointer<Uint16>,
      Uint32,
      Uint32,
      Pointer<Uint8>,
      Pointer<IntPtr>,
      Pointer<Uint32>,
    );
typedef _RegCreateKeyExWDart =
    int Function(
      int,
      Pointer<Uint16>,
      int,
      Pointer<Uint16>,
      int,
      int,
      Pointer<Uint8>,
      Pointer<IntPtr>,
      Pointer<Uint32>,
    );
typedef _RegDeleteValueWNative = Int32 Function(IntPtr, Pointer<Uint16>);
typedef _RegDeleteValueWDart = int Function(int, Pointer<Uint16>);
typedef _RegSetValueExWNative =
    Int32 Function(
      IntPtr,
      Pointer<Uint16>,
      Uint32,
      Uint32,
      Pointer<Uint8>,
      Uint32,
    );
typedef _RegSetValueExWDart =
    int Function(int, Pointer<Uint16>, int, int, Pointer<Uint8>, int);
typedef _RegQueryValueExWNative =
    Int32 Function(
      IntPtr,
      Pointer<Uint16>,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint8>,
      Pointer<Uint32>,
    );
typedef _RegQueryValueExWDart =
    int Function(
      int,
      Pointer<Uint16>,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint8>,
      Pointer<Uint32>,
    );
typedef _RegCloseKeyWNative = Int32 Function(IntPtr);
typedef _RegCloseKeyWDart = int Function(int);

abstract final class _Advapi32 {
  static final DynamicLibrary lib = DynamicLibrary.open('advapi32.dll');

  static final _RegOpenKeyExWDart regOpenKeyExW = lib
      .lookupFunction<_RegOpenKeyExWNative, _RegOpenKeyExWDart>(
        'RegOpenKeyExW',
      );
  static final _RegCreateKeyExWDart regCreateKeyExW = lib
      .lookupFunction<_RegCreateKeyExWNative, _RegCreateKeyExWDart>(
        'RegCreateKeyExW',
      );
  static final _RegDeleteValueWDart regDeleteValueW = lib
      .lookupFunction<_RegDeleteValueWNative, _RegDeleteValueWDart>(
        'RegDeleteValueW',
      );
  static final _RegSetValueExWDart regSetValueExW = lib
      .lookupFunction<_RegSetValueExWNative, _RegSetValueExWDart>(
        'RegSetValueExW',
      );
  static final _RegQueryValueExWDart regQueryValueExW = lib
      .lookupFunction<_RegQueryValueExWNative, _RegQueryValueExWDart>(
        'RegQueryValueExW',
      );
  static final _RegCloseKeyWDart regCloseKeyW = lib
      .lookupFunction<_RegCloseKeyWNative, _RegCloseKeyWDart>('RegCloseKeyW');
}

abstract final class AutoStartOps {
  static bool get enabled {
    final phKey = calloc<IntPtr>();
    try {
      if (_Advapi32.regOpenKeyExW(
            AutoStart._hkeyCurrentUser,
            AutoStart._toUtf16(AutoStart._subKey),
            0,
            AutoStart._keyRead,
            phKey,
          ) !=
          AutoStart._errorSuccess) {
        return false;
      }
      final type = calloc<Uint32>();
      final size = calloc<Uint32>();
      try {
        return _Advapi32.regQueryValueExW(
              phKey.value,
              AutoStart._toUtf16(AutoStart._valueName),
              nullptr.cast(),
              type,
              nullptr,
              size,
            ) ==
            AutoStart._errorSuccess;
      } finally {
        calloc.free(type);
        calloc.free(size);
        _Advapi32.regCloseKeyW(phKey.value);
      }
    } finally {
      calloc.free(phKey);
    }
  }

  /// returns whether the registry now reflects the requested state
  static bool setEnabled(bool enable) {
    final phKey = calloc<IntPtr>();
    try {
      if (_Advapi32.regCreateKeyExW(
            AutoStart._hkeyCurrentUser,
            AutoStart._toUtf16(AutoStart._subKey),
            0,
            nullptr,
            AutoStart._regOptionNonVolatile,
            AutoStart._keySetValue,
            nullptr,
            phKey,
            nullptr,
          ) !=
          AutoStart._errorSuccess) {
        return false;
      }
      if (enable) {
        // quote the path so spaces are handled by the shell
        final exe = '"${Platform.resolvedExecutable}"';
        final data = AutoStart._toUtf16(exe);
        try {
          return _Advapi32.regSetValueExW(
                phKey.value,
                AutoStart._toUtf16(AutoStart._valueName),
                0,
                AutoStart._regSz,
                data.cast<Uint8>(),
                (exe.codeUnits.length + 1) * 2,
              ) ==
              AutoStart._errorSuccess;
        } finally {
          calloc.free(data);
        }
      }
      final deleted =
          _Advapi32.regDeleteValueW(
            phKey.value,
            AutoStart._toUtf16(AutoStart._valueName),
          ) ==
          AutoStart._errorSuccess;
      return deleted || !AutoStart.enabled;
    } finally {
      _Advapi32.regCloseKeyW(phKey.value);
      calloc.free(phKey);
    }
  }
}
