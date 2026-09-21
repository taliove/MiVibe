#pragma once

// ggml-version.h 正常由 CMake configure_file 生成；本项目用 SwiftPM 直接编译
// vendored 源码，没有 CMake 环节，所以提供一个静态版本。升级 whisper.cpp
// （Scripts/fetch-whisper.sh 里的 VERSION）时同步更新这里。
#define GGML_VERSION "1.9.4"
#define GGML_COMMIT  "vendored-v1.9.4"
