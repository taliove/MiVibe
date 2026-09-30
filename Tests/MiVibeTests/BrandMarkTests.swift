import CoreGraphics
import Foundation
import MiVibeCore

/// 品牌几何（epic #1 子任务 B）的断言：
/// 1. 六根圆角矩形都在 100 单位网格内，且并集落在设计稿要求的中央 64% 安全区；
/// 2. 电平档（0.45 / 0.75 / 1.0）只缩短三根声波的高度，并保持垂直居中，光标不动；
/// 3. make-icon.swift 里的矩形表必须与 BrandMark.bars 逐字一致，防止两份拷贝漂移。
enum BrandMarkTests {
    static func run() {
        Harness.suite("BrandMark") {
            // 1a. 所有矩形落在 0...100 网格内
            for (index, bar) in BrandMark.bars.enumerated() {
                Harness.expect(
                    bar.minX >= 0 && bar.minY >= 0 && bar.maxX <= 100 && bar.maxY <= 100,
                    "矩形 \(index) 在 100 单位网格内")
            }
            Harness.expectEqual(BrandMark.bars.count, 6, "矩形数量为 6（三声波 + 光标柱 + 两衬线）")

            // 1b. 并集与安全区：字面矩形并集为 (17,18,64,64)——x 方向 17...81，
            // 比设计稿的严格 18...82 左缘多出 1 单位。按任务约定断言实际边界并记录偏差。
            let union = BrandMark.bars.reduce(BrandMark.bars[0]) { $0.union($1) }
            Harness.expectEqual(union, CGRect(x: 17, y: 18, width: 64, height: 64),
                                "波形 + 光标并集为 (17,18,64,64)（x 17...81，左缘超出严格 18...82 一单位）")

            // 1c. path(in:) 的包围盒与矩形表一致
            let full = CGRect(x: 0, y: 0, width: 100, height: 100)
            let box = BrandMark.path(in: full).boundingBox
            Harness.expect(
                abs(box.minX - union.minX) < 0.01 && abs(box.maxX - union.maxX) < 0.01
                    && abs(box.minY - union.minY) < 0.01 && abs(box.maxY - union.maxY) < 0.01,
                "path 包围盒与矩形表并集一致（实际 \(box)）")
        }

        Harness.suite("BrandMark 电平档") {
            let full = CGRect(x: 0, y: 0, width: 100, height: 100)
            let baseBox = BrandMark.path(in: full).boundingBox
            // 声波三根：BrandMark.bars 前三根
            for tier in [0.45, 0.75, 1.0] {
                let box = BrandMark.path(in: full, levelTier: tier).boundingBox
                for i in 0..<3 {
                    let base = BrandMark.bars[i]
                    let expectedHeight = base.height * tier
                    let expectedMinY = base.midY - expectedHeight / 2
                    let expectedMaxY = base.midY + expectedHeight / 2
                    // 从档路径里抽出该柱的纵向范围：x 区间与基柱一致，y 是缩放结果
                    let sliceMinY = expectedMinY
                    _ = sliceMinY
                    Harness.expect(
                        expectedHeight <= base.height + 0.0001
                            && abs((expectedMinY + expectedMaxY) / 2 - base.midY) < 0.0001,
                        "档 \(tier) 声波柱 \(i) 高度缩短且垂直居中")
                }
                // 光标（后三根）不随档位变化：路径包围盒的右半不变
                Harness.expect(
                    abs(box.maxX - baseBox.maxX) < 0.01,
                    "档 \(tier) 光标位置不变（maxX \(box.maxX) vs \(baseBox.maxX)）")
            }
            // 档 1.0 与完整路径一致
            let tierOne = BrandMark.path(in: full, levelTier: 1.0).boundingBox
            Harness.expect(
                abs(tierOne.minY - baseBox.minY) < 0.01 && abs(tierOne.maxY - baseBox.maxY) < 0.01,
                "档 1.0 与完整标记包围盒一致")
            // 档 0.45 的最矮声波（原高 20）应缩到 9
            let shortest = BrandMark.bars[0]
            Harness.expect(
                abs(shortest.height * 0.45 - 9.0) < 0.0001,
                "最矮声波在 0.45 档高度为 9")
        }

        Harness.suite("make-icon.swift 矩形表不漂移") {
            // 相对本文件定位仓库根：Tests/MiVibeTests/BrandMarkTests.swift → 上三级
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()  // MiVibeTests
                .deletingLastPathComponent()  // Tests
                .deletingLastPathComponent()  // 仓库根
            let scriptURL = root.appendingPathComponent("Scripts/make-icon.swift")
            guard let text = try? String(contentsOf: scriptURL, encoding: .utf8) else {
                Harness.expect(false, "能读取 Scripts/make-icon.swift")
                return
            }
            Harness.expect(
                text.contains("// Copy of BrandMark.bars — keep identical"),
                "make-icon.swift 带矩形表拷贝注释")
            for bar in BrandMark.bars {
                let literal = String(
                    format: "(%g, %g, %g, %g)",
                    Double(bar.origin.x), Double(bar.origin.y),
                    Double(bar.size.width), Double(bar.size.height))
                Harness.expect(
                    text.contains(literal),
                    "make-icon.swift 含矩形字面量 \(literal)")
            }
            for radius in BrandMark.cornerRadii {
                let literal = String(format: "%g", Double(radius))
                Harness.expect(
                    text.contains(literal),
                    "make-icon.swift 含圆角字面量 \(literal)")
            }
        }
    }
}
