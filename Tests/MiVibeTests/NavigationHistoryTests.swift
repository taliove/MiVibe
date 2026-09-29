import MiVibeCore

/// 设置窗口前进 / 后退历史的验收。
enum NavigationHistoryTests {
    static func run() {
        Harness.suite("NavigationHistory") {
            // 初始：只有一项，既不能后退也不能前进。
            var h = NavigationHistory(initial: "a")
            Harness.expectEqual(h.current, "a", "初始 current 为初始项")
            Harness.expect(!h.canGoBack, "初始不能后退")
            Harness.expect(!h.canGoForward, "初始不能前进")
            Harness.expectEqual(h.goBack() as String?, nil, "初始 goBack 返回 nil")
            Harness.expectEqual(h.goForward() as String?, nil, "初始 goForward 返回 nil")
            Harness.expectEqual(h.current, "a", "无效 back/forward 后状态不变")

            // visit 压栈；同项 visit 无副作用。
            h.visit("b")
            Harness.expectEqual(h.current, "b", "visit 更新 current")
            Harness.expect(h.canGoBack, "visit 后可以后退")
            Harness.expect(!h.canGoForward, "visit 后不能前进")
            h.visit("b")
            Harness.expectEqual(h.current, "b", "visit 同项 current 不变")
            h.goBack()
            Harness.expectEqual(h.current, "a", "visit 同项后只需一次后退即回到 a")
            Harness.expect(!h.canGoBack, "visit 同项未重复压栈")
            h.goForward()
            Harness.expectEqual(h.current, "b", "回到 b 后继续测试")

            // back / forward 往返（当前 b，历史 a → b → c）。
            h.visit("c")
            Harness.expectEqual(h.goBack() as String?, "b", "goBack 返回新 current")
            Harness.expectEqual(h.current, "b", "goBack 后 current 回退")
            Harness.expect(h.canGoBack, "回退后仍可再退")
            Harness.expect(h.canGoForward, "回退后可以前进")
            Harness.expectEqual(h.goForward() as String?, "c", "goForward 返回新 current")
            Harness.expectEqual(h.current, "c", "goForward 后 current 前进")
            Harness.expect(!h.canGoForward, "前进栈用尽后不能前进")

            // 后退后 visit 新项：前进栈清空。
            h.goBack()
            h.visit("x")
            Harness.expectEqual(h.current, "x", "回退后 visit 新项")
            Harness.expect(!h.canGoForward, "visit 新项后前进栈被清空")
            Harness.expectEqual(h.goBack() as String?, "b", "回退后 visit 的后退链正确")

            // 上限截断：超过上限丢最旧的历史。
            var capped = NavigationHistory(initial: 0)
            for i in 1...60 { capped.visit(i) }
            Harness.expectEqual(capped.current, 60, "上限测试 current 为最后一项")
            var backCount = 0
            while capped.goBack() != nil { backCount += 1 }
            Harness.expectEqual(backCount, NavigationHistory<Int>.capacity - 1,
                                "可回退步数等于上限减一（最旧的被丢弃）")
            Harness.expectEqual(capped.current, 60 - (NavigationHistory<Int>.capacity - 1),
                                "截断后最早可回退项正确")
        }
    }
}
