import Testing
@testable import WebPortingKit

private struct TestContextKeys {
    var userID: String { "" }
    var traceID: String { "" }
    var retryCount: Int { 0 }
}

private protocol TestContextService: Sendable {}
private struct TestContextServiceImplementation: TestContextService {}

@Suite("Request context storage")
struct RequestContextTests {
    @Test("key paths isolate values of the same type")
    func keyPathsIsolateValuesOfTheSameType() async {
        let context = RequestContext()

        await context.set("user-1", for: \TestContextKeys.userID)
        await context.set("trace-1", for: \TestContextKeys.traceID)

        #expect(await context.get(\TestContextKeys.userID) == "user-1")
        #expect(await context.get(\TestContextKeys.traceID) == "trace-1")
    }

    @Test("key path removal only removes the matching key")
    func keyPathRemovalOnlyRemovesMatchingKey() async {
        let context = RequestContext()

        await context.set("user-1", for: \TestContextKeys.userID)
        await context.set("trace-1", for: \TestContextKeys.traceID)
        await context.remove(\TestContextKeys.userID)

        #expect(await context.get(\TestContextKeys.userID) == nil)
        #expect(await context.get(\TestContextKeys.traceID) == "trace-1")
    }

    @Test("key paths preserve value type")
    func keyPathsPreserveValueType() async {
        let context = RequestContext()

        await context.set(3, for: \TestContextKeys.retryCount)

        #expect(await context.get(\TestContextKeys.retryCount) == 3)
    }

    @Test("type based storage remains available for compatibility")
    func typeBasedStorageRemainsAvailableForCompatibility() async {
        let context = RequestContext()

        await context.set("value")

        #expect(await context.get(String.self) == "value")
    }

    @Test("type based storage respects explicit type keys")
    func typeBasedStorageRespectsExplicitTypeKeys() async {
        let context = RequestContext()

        await context.set(TestContextServiceImplementation() as any TestContextService, as: (any TestContextService).self)

        #expect(await context.get((any TestContextService).self) != nil)
        #expect(await context.get(TestContextServiceImplementation.self) == nil)
    }
}
