# Third-party notices

MiVibe 的发布包内含以下第三方软件。MiVibe release builds include the following third-party software.

## whisper.cpp / ggml (v1.9.4)

- 来源 Source: https://github.com/ggml-org/whisper.cpp
- 用途 Use: 本地离线语音识别，编译进 MiVibe 可执行文件，Metal 内核随包分发。Offline speech recognition, compiled into the MiVibe executable; its Metal kernels ship in the app bundle.
- 许可 License: MIT

```
MIT License

Copyright (c) 2023-2026 The ggml authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Whisper 模型 · Whisper models

本地识别模型不随安装包分发，由用户在设置中按需下载。模型由 OpenAI 以 MIT 许可发布。
Local recognition models are not bundled; users download them on demand in Settings. The models are released by OpenAI under the MIT license.
