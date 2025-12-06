# dart:ffiを用いてC＋＋コードをiOS/Androidから呼び出す

## 1. ネイティブ実装を作成
iOSではXCodeにの都合上 `Classes`ディレクトリへのドラッグドロップが必要なのでこちらに実装

`ios/Classes/native_add.cpp`
```cpp
#include <stdint.h>
#include <stdio.h>

extern "C" __attribute__((visibility("default"))) __attribute__((used))
int32_t
native_add(int32_t x, int32_t y)
{
    printf("native_add is called!");
    return x + y;
}
```

## 2. AndroidでCmakeLists.txtとbuild.gradle.ktsを設定
`android/app/CMakeLists.txt`
```cmake
cmake_minimum_required(VERSION 3.4.1)
add_library(native_add
              SHARED
              ../../ios/Classes/native_add.cpp)
```

`android/app/build.gradle.kts`

```kotlin
android {
    ...
    externalNativeBuild {
        cmake {
            path = file("CMakeLists.txt")
        }
    }
}
```

## 3. Dartコードでネイティブ関数を呼び出す
`lib/main.dart`
```dart
import 'dart:ffi';
import 'dart:io';

final DynamicLibrary nativeAddLib = Platform.isAndroid
    ? DynamicLibrary.open('libnative_add.so')
    : DynamicLibrary.process();

final int Function(int x, int y) nativeAdd = nativeAddLib
    .lookup<NativeFunction<Int32 Function(Int32, Int32)>>('native_add')
    .asFunction();
```
