import 'dart:io';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Initializes the sqflite database factory for the current platform.
///
/// On Windows (and other desktop targets where the native sqflite plugin is
/// not available) we must switch to the FFI factory. Call once at startup
/// before any database access.
void initDatabaseFactory() {
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  // macOS/iOS use the default native sqflite factory.
}

/// Force the FFI factory regardless of platform. Used by unit tests so they can
/// run the vault index against a real SQLite engine on any host.
void useFfiDatabaseFactoryForTests() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}
