@testable import DataKit
import Foundation
import Testing

@Suite struct AccountServiceTests {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func exportWritesAShareableFile() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = FakeAccountService(directory: directory)
        let url = try await service.exportData(userId: testUser)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.pathExtension == "json")
        #expect(try String(contentsOf: url, encoding: .utf8).contains(testUser.uuidString))
        #expect(await service.exportedUsers == [testUser])
    }

    @Test func deleteIsRecorded() async throws {
        let service = FakeAccountService()
        try await service.deleteAccount(userId: testUser)
        #expect(await service.deletedUsers == [testUser])
    }

    @Test func failuresPropagateAndRecordNothing() async throws {
        let service = FakeAccountService(shouldFail: true)
        await #expect(throws: AccountError.failed) { try await service.deleteAccount(userId: testUser) }
        await #expect(throws: AccountError.failed) { _ = try await service.exportData(userId: testUser) }
        #expect(await service.deletedUsers.isEmpty)
        await service.setShouldFail(false)
        try await service.deleteAccount(userId: testUser)
        #expect(await service.deletedUsers == [testUser])
    }
}
