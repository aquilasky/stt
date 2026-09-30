import AppKit
import SwiftUI
import Testing
@testable import LectureCaption

@Test func configurationDestinationsHaveDistinctToolbarRoutes() {
    #expect(ConfigurationDestination.allCases == [.course, .api])
    #expect(ConfigurationDestination.course.id != ConfigurationDestination.api.id)
    #expect(ConfigurationDestination.course.title == "课程配置")
    #expect(ConfigurationDestination.api.title == "API 配置")
}

@Test @MainActor func courseFormEditsSharedStateWithoutChangingAPIConfiguration() async throws {
    let state = AppState()
    state.courseName = "Original course"
    state.topic = "Original topic"
    state.aliyunWorkspaceID = "test-workspace"
    state.aliyunRegion = .singapore
    state.aliyunAPIKey = "synthetic-aliyun-value"
    state.deepSeekAPIKey = "synthetic-deepseek-value"
    state.glossary = [GlossaryEntry(source: "gradient", target: "梯度")]
    state.phase = .recognizing

    let host = NSHostingView(rootView: CourseConfigurationView(appState: state))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 680), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.isReleasedWhenClosed = false
    defer { window.close() }
    host.frame = NSRect(x: 0, y: 0, width: 500, height: 680)
    host.layoutSubtreeIfNeeded()
    await Task.yield()
    let fields = configurationTextFields(in: host)
    let course = try #require(fields.first { $0.stringValue == "Original course" })
    let topic = try #require(fields.first { $0.stringValue == "Original topic" })
    editConfigurationField(course, text: "Machine Learning")
    editConfigurationField(topic, text: "Optimization")
    let glossarySource = try #require(fields.first { $0.stringValue == "gradient" })
    let glossaryTarget = try #require(fields.first { $0.stringValue == "梯度" })
    editConfigurationField(glossarySource, text: "gradient descent")
    editConfigurationField(glossaryTarget, text: "梯度下降")

    #expect(state.courseName == "Machine Learning")
    #expect(state.topic == "Optimization")
    #expect(state.aliyunWorkspaceID == "test-workspace")
    #expect(state.aliyunRegion == .singapore)
    #expect(state.aliyunAPIKey == "synthetic-aliyun-value")
    #expect(state.deepSeekAPIKey == "synthetic-deepseek-value")
    #expect(state.glossary.first?.source == "gradient descent")
    #expect(state.glossary.first?.target == "梯度下降")
    #expect(state.phase == .recognizing)
    #expect(!fields.contains { $0 is NSSecureTextField })

    let reopened = NSHostingView(rootView: CourseConfigurationView(appState: state))
    window.contentView = reopened
    reopened.layoutSubtreeIfNeeded()
    await Task.yield()
    let reopenedFields = configurationTextFields(in: reopened)
    #expect(reopenedFields.contains { $0.stringValue == "Machine Learning" })
    #expect(reopenedFields.contains { $0.stringValue == "Optimization" })
    #expect(reopenedFields.contains { $0.stringValue == "梯度下降" })
}

@Test @MainActor func apiFormKeepsSecureFieldsAndCourseContext() async throws {
    let state = AppState()
    state.courseName = "Machine Learning"
    state.topic = "Optimization"
    state.sourceLanguage = .english
    state.targetLanguage = .simplifiedChinese
    state.glossary = [GlossaryEntry(source: "gradient", target: "梯度")]
    state.aliyunWorkspaceID = "original-workspace"
    state.aliyunAPIKey = "original-aliyun-value"
    state.deepSeekAPIKey = "original-deepseek-value"

    let host = NSHostingView(rootView: APIConfigurationView(appState: state))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 680), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = host
    window.isReleasedWhenClosed = false
    defer { window.close() }
    host.frame = NSRect(x: 0, y: 0, width: 500, height: 680)
    host.layoutSubtreeIfNeeded()
    await Task.yield()
    let fields = configurationTextFields(in: host)
    let workspace = try #require(fields.first { $0.stringValue == "original-workspace" })
    let aliyunKey = try #require(fields.first { $0.stringValue == "original-aliyun-value" })
    let deepSeekKey = try #require(fields.first { $0.stringValue == "original-deepseek-value" })
    #expect(aliyunKey is NSSecureTextField)
    #expect(deepSeekKey is NSSecureTextField)
    editConfigurationField(workspace, text: "test-workspace")
    editConfigurationField(aliyunKey, text: "synthetic-aliyun-value")
    editConfigurationField(deepSeekKey, text: "synthetic-deepseek-value")

    #expect(state.aliyunWorkspaceID == "test-workspace")
    #expect(state.aliyunAPIKey == "synthetic-aliyun-value")
    #expect(state.deepSeekAPIKey == "synthetic-deepseek-value")
    #expect(state.courseName == "Machine Learning")
    #expect(state.topic == "Optimization")
    #expect(state.sourceLanguage == .english)
    #expect(state.targetLanguage == .simplifiedChinese)
    #expect(state.glossary.first?.source == "gradient")

    let reopened = NSHostingView(rootView: APIConfigurationView(appState: state))
    window.contentView = reopened
    reopened.layoutSubtreeIfNeeded()
    await Task.yield()
    let reopenedFields = configurationTextFields(in: reopened)
    #expect(reopenedFields.contains { $0.stringValue == "test-workspace" })
    #expect(reopenedFields.contains { $0.stringValue == "synthetic-aliyun-value" })
    #expect(reopenedFields.contains { $0.stringValue == "synthetic-deepseek-value" })
}

@MainActor private func configurationTextFields(in view: NSView) -> [NSTextField] {
    (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { configurationTextFields(in: $0) }
}

@MainActor private func editConfigurationField(_ field: NSTextField, text: String) {
    field.stringValue = text
    field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
}
