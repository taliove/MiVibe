// MiVibe 测试入口：`swift run MiVibeTests`
// 本机无 Xcode，XCTest/swift-testing 不可用，详见 Harness.swift 说明。

print("MiVibe 测试")
print(String(repeating: "═", count: 52))

ADPCMTests.run()
DoubaoFrameTests.run()
InputQueueTests.run()
InputQueueEmptyResultTests.run()
RecordingTriageTests.run()
AudioLevelTests.run()
KeyMappingTests.run()
NavigationHistoryTests.run()
ModeAndActionTests.run()
KeywordCorrectionTests.run()
PendingStoreTests.run()
TakeoverFailureTests.run()
RemoteKeyRemapTests.run()
ThemeTests.run()
BrandMarkTests.run()

Harness.finish()
