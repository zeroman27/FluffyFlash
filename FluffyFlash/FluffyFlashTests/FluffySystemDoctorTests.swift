//
//  FluffySystemDoctorTests.swift
//  FluffyFlashTests
//
//  Sanity-checks the System Status report shape the Settings card relies on.
//  Does not exercise SMJobBless / TCC paths — only the in-process aggregation
//  + plain-text formatter.
//

import Foundation
import Testing
@testable import Wist

@MainActor
struct FluffySystemDoctorTests {

    @Test("runDiagnostics produces all four sections")
    func reportSectionsArePopulated() async {
        let doctor = FluffySystemDoctor()
        await doctor.runDiagnostics()
        let report = doctor.report
        #expect(report != nil)
        let ids = report?.sections.map(\.id) ?? []
        #expect(ids.contains("bundled-tools"))
        #expect(ids.contains("permissions"))
        #expect(ids.contains("environment"))
        #expect(ids.contains("storage"))
    }

    @Test("Plain-text report contains every section header")
    func plainTextReportRenders() async {
        let doctor = FluffySystemDoctor()
        await doctor.runDiagnostics()
        let plain = doctor.report?.plainTextReport() ?? ""
        #expect(plain.contains("Fluffy Flash"))
        #expect(plain.contains("Bundled CLI tools"))
        #expect(plain.contains("Permissions"))
        #expect(plain.contains("Environment"))
        #expect(plain.contains("Storage"))
    }

    @Test("Section rollup is the worst status of its items")
    func rollupIsWorstStatus() {
        let okItem = SystemCheckItem(
            id: "a", title: "A", detail: nil, status: .ok,
            fixAction: nil, fixLabel: nil
        )
        let warnItem = SystemCheckItem(
            id: "b", title: "B", detail: nil, status: .warning("warn"),
            fixAction: nil, fixLabel: nil
        )
        let failItem = SystemCheckItem(
            id: "c", title: "C", detail: nil, status: .failed("fail"),
            fixAction: nil, fixLabel: nil
        )
        let mixed = SystemStatusSection(
            id: "x", title: "X", symbol: "circle",
            items: [okItem, warnItem, failItem]
        )
        if case .failed(let msg) = mixed.rollupStatus {
            #expect(msg == "fail")
        } else {
            Issue.record("Rollup should be `.failed` when any item is failed")
        }

        let onlyOK = SystemStatusSection(
            id: "y", title: "Y", symbol: "circle",
            items: [okItem, okItem]
        )
        #expect(onlyOK.rollupStatus == .ok)
    }

    @Test("Idempotent re-run replaces the previous report")
    func reRunReplacesReport() async {
        let doctor = FluffySystemDoctor()
        await doctor.runDiagnostics()
        let firstDate = doctor.report?.generatedAt
        try? await Task.sleep(nanoseconds: 30_000_000)
        await doctor.runDiagnostics()
        let secondDate = doctor.report?.generatedAt
        #expect(firstDate != nil)
        #expect(secondDate != nil)
        #expect(firstDate! <= secondDate!)
    }
}
