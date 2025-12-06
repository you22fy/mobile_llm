// iosフォルダの中のファイルをandroidでも参照する構成にしていきます。
#include <stdint.h>
#include <stdio.h>

extern "C" __attribute__((visibility("default"))) __attribute__((used))
int32_t
native_add(int32_t x, int32_t y)
{
    printf("native_add is called!");
    return x + y;
}
