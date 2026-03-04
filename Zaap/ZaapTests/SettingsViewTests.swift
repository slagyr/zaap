import XCTest
import SwiftUI
@testable import Zaap

final class SettingsViewTests: XCTestCase {

    func testSettingsViewIsAView() {
        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let view = SettingsView(settings: settings)
        XCTAssertNotNil(view.body)
    }

    func testTokenLabelPropertiesExist() {
        let settings = SettingsManager(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        let view = SettingsView(settings: settings)
        XCTAssertEqual(view.hooksTokenLabel, "Hooks Bearer Token")
        XCTAssertEqual(view.gatewayTokenLabel, "Gateway Bearer Token")
    }

    func testVoiceSectionClosesBeforeDataSourcesSection() {
        // This test verifies that the Voice section and Data Sources section
        // are sibling Sections in the Form, not nested. A missing closing brace
        // on the Voice section would cause the Data Sources section to be
        // swallowed inside the Voice header closure, making it invisible.
        let source = try! String(contentsOfFile: #filePath.replacingOccurrences(
            of: "ZaapTests/SettingsViewTests.swift",
            with: "Zaap/SettingsView.swift"
        ))
        let lines = source.components(separatedBy: "\n")

        // Find the line with header text "Voice"
        let voiceHeaderLine = lines.firstIndex { $0.contains("Text(\"Voice\")") }
        XCTAssertNotNil(voiceHeaderLine, "Expected to find Text(\"Voice\") in SettingsView.swift")

        // Find the line with "Section {" that contains Data Sources
        let dataSourcesSectionLine = lines.firstIndex { $0.contains("Text(\"Data Sources\")") }
        XCTAssertNotNil(dataSourcesSectionLine, "Expected to find Text(\"Data Sources\") in SettingsView.swift")

        // Between the Voice header text and the Data Sources section header,
        // there must be a closing brace "}" that ends the Voice Section.
        // Specifically, the line after Text("Voice") should be a lone "}"
        // before the Data Sources Section { starts.
        guard let voiceLine = voiceHeaderLine, let dataLine = dataSourcesSectionLine else { return }
        XCTAssertTrue(voiceLine < dataLine, "Voice header should appear before Data Sources header")

        let linesBetween = lines[(voiceLine + 1)..<dataLine]
        let closingBraceCount = linesBetween.filter { $0.trimmingCharacters(in: .whitespaces) == "}" }.count
        let sectionOpenCount = linesBetween.filter { $0.trimmingCharacters(in: .whitespaces) == "Section {" || $0.contains("Section {") }.count

        // The Voice Section must be closed (at least one standalone "}" that closes it)
        // before a new Section opens for Data Sources.
        // In the broken state, there's no closing "}" between Text("Voice") and Section {
        XCTAssertGreaterThanOrEqual(closingBraceCount, sectionOpenCount,
            "Voice section must be closed before Data Sources section opens. " +
            "Found \(closingBraceCount) closing braces and \(sectionOpenCount) section opens between Voice and Data Sources headers.")
    }
}
