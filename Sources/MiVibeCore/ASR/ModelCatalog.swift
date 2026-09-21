import Foundation

/// 语音模型目录：硬编码在 App 内（含下载源与 SHA256），不做远程下发。
/// ggml 官方仓库在 ModelScope 上没有同名镜像，国内可达性最好的主源是
/// hf-mirror.com（HuggingFace 的国内镜像），HuggingFace 官方作为备用源。
public enum ModelCatalog {
    public struct Model: Sendable, Identifiable, Equatable {
        /// 目录内 id（如 "small"），也是 config.json 里 `localModel` 的值。
        public let id: String
        public let fileName: String
        public let displayName: String
        public let sizeBytes: Int64
        public let sha256: String
        /// 相对速度与质量的一句话描述（设置页用）。
        public let speedNote: String
        public let qualityNote: String

        public var sizeText: String {
            ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
        }

        /// 主源（hf-mirror）在前，备用源（HuggingFace 官方）在后。
        public var downloadURLs: [URL] {
            [
                URL(string: "https://hf-mirror.com/ggerganov/whisper.cpp/resolve/main/\(fileName)")!,
                URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")!,
            ]
        }
    }

    public static let all: [Model] = [
        Model(id: "tiny", fileName: "ggml-tiny.bin", displayName: "Tiny",
              sizeBytes: 77_691_713,
              sha256: "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21",
              speedNote: "最快", qualityNote: "错字较多，适合应急"),
        Model(id: "base", fileName: "ggml-base.bin", displayName: "Base",
              sizeBytes: 147_951_465,
              sha256: "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe",
              speedNote: "快", qualityNote: "日常短句够用"),
        Model(id: "small", fileName: "ggml-small.bin", displayName: "Small",
              sizeBytes: 487_601_967,
              sha256: "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b",
              speedNote: "较快", qualityNote: "质量与速度的平衡点"),
        Model(id: "medium", fileName: "ggml-medium.bin", displayName: "Medium",
              sizeBytes: 1_533_763_059,
              sha256: "6c14d5adee5f86394037b4e4e8b59f1673b6cee10e3cf0b11bbdbee79c156208",
              speedNote: "较慢", qualityNote: "质量好，内存压力大"),
        Model(id: "large-v3-turbo", fileName: "ggml-large-v3-turbo.bin", displayName: "Large (Turbo)",
              sizeBytes: 1_624_555_275,
              sha256: "1fc70f774d38eb169993ac391eea357ef47c88757ef72ee5943879b7e8e2bc69",
              speedNote: "中速", qualityNote: "接近最高质量，M 系芯片甜点位"),
    ]

    public static func model(id: String?) -> Model? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }
}

/// 硬件推荐：按内存档位映射（Apple Silicon），Intel Mac 整体降一档。
/// medium 从不主动推荐（标注"可用但偏慢"），由用户自行选择。
public enum HardwareProfile {
    /// 运行架构即芯片架构（本应用只本机构建本机运行）。
    public static var isAppleSilicon: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    public static var memoryGB: Double {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    }

    public static var recommendedModelID: String {
        let gb = memoryGB
        let level: Int
        if gb >= 32 { level = 4 }        // large-v3-turbo
        else if gb >= 16 { level = 2 }   // small
        else if gb >= 8 { level = 1 }    // base
        else { level = 0 }               // tiny
        let adjusted = isAppleSilicon ? level : max(0, level - 1)
        switch adjusted {
        case 4: return "large-v3-turbo"
        case 2: return "small"
        case 1: return "base"
        default: return "tiny"
        }
    }
}
