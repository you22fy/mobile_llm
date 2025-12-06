import 'dart:ffi'; // For FFI
import 'dart:io'; // For Platform.isX

// ネイティブライブラリをロードするためのDynamicLibraryオブジェクトを作成
final DynamicLibrary nativeAddLib = Platform.isAndroid
    ? DynamicLibrary.open('libnative_add.so')
    : DynamicLibrary.process();

// DynamicLibraryオブジェクトから検索された関数をDartの関数型に変換
final int Function(int x, int y) nativeAdd = nativeAddLib
    .lookup<NativeFunction<Int32 Function(Int32, Int32)>>('native_add')
    .asFunction();
