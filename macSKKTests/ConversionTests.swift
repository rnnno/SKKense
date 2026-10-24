// SPDX-FileCopyrightText: 2026 mtgto <hogerappa@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import XCTest

@testable import macSKK

final class ConversionTests: XCTestCase {
    private static let readonlyEntries: [String: [Word]] = [
        "かく": [Word("各"), Word("角"), Word("格"), Word("核"), Word("画"), Word("確"), Word("閣")],
        "かk": [Word("書"), Word("掛"), Word("欠")],
        "きく": [Word("菊")],
        "きk": [Word("聞"), Word("効")],
        "かんがe": [Word("考")],
        "かn": [Word("兼")],
        "まちが": [Word("待画")],
        "まt": [Word("待")],
        "むずかs": [Word("難")],
        "おおk": [Word("多"), Word("大", okuri: "き")],
    ]

    override func setUp() async throws {
        try await MainActor.run {
            Global.dictionary = try UserDict(dicts: [MemoryDict(entries: Self.readonlyEntries, readonly: true)],
                                                 privateMode: CurrentValueSubject(false),
                                                 ignoreUserDictInPrivateMode: CurrentValueSubject(false),
                                                 dateYomis: [],
                                                 dateConversions: [])
            Global.dictionary.setEntries([:])
            Global.skkservDict = nil
            Global.autoOkuri = true
        }
    }

    override func tearDown() async throws {
        await MainActor.run {
            Global.autoOkuri = false
        }
    }

    @MainActor func testKaku() {
        let candidates = Global.conversion.candidates(yomi: "かく", inputMode: .hiragana)
        XCTAssertEqual(candidates.map(\.word), ["各", "角", "格", "書く", "掛く", "欠く", "核", "画", "確", "閣"])
        XCTAssertEqual(candidates.first { $0.word == "書く" }?.original,
                       Candidate.Original(midashi: "かk", word: "書", okuri: "く"))
    }

    @MainActor func testKangaeru() {
        let words = Global.conversion.candidates(yomi: "かんがえる", inputMode: .hiragana).map(\.word)
        XCTAssertTrue(words.contains("考える"))
        XCTAssertFalse(words.contains("兼んがえる"))
    }

    @MainActor func testMatiga() {
        XCTAssertEqual(Global.conversion.candidates(yomi: "まちが", inputMode: .hiragana).map(\.word), ["待画"])
    }

    @MainActor func testMuzukashii() {
        XCTAssertEqual(Global.conversion.candidates(yomi: "むずかしい", inputMode: .hiragana).map(\.word), ["難しい"])
    }

    @MainActor func testOkuriBlockFilter() {
        XCTAssertEqual(Global.conversion.candidates(yomi: "おおきい", inputMode: .hiragana).map(\.word),
                       ["大きい", "多きい"])
    }

    @MainActor func testUserDictFirst() {
        Global.dictionary.add(yomi: "かk", word: Word("書", okuri: "く"), source: .conversion)
        XCTAssertEqual(Global.conversion.candidates(yomi: "かく", inputMode: .hiragana).first?.word, "書く")
    }

    @MainActor func testPrivateModeIgnoresUserDict() throws {
        let privateMode = CurrentValueSubject<Bool, Never>(false)
        let ignoreUserDictInPrivateMode = CurrentValueSubject<Bool, Never>(false)
        Global.dictionary = try UserDict(dicts: [MemoryDict(entries: Self.readonlyEntries, readonly: true)],
                                         privateMode: privateMode,
                                         ignoreUserDictInPrivateMode: ignoreUserDictInPrivateMode,
                                         dateYomis: [],
                                         dateConversions: [])
        Global.dictionary.setEntries([:])
        Global.dictionary.add(yomi: "かk", word: Word("書", okuri: "く"), source: .conversion)
        privateMode.send(true)
        ignoreUserDictInPrivateMode.send(true)
        XCTAssertEqual(Global.conversion.candidates(yomi: "かく", inputMode: .hiragana).map(\.word),
                       ["各", "角", "格", "書く", "掛く", "欠く", "核", "画", "確", "閣"])
    }

    @MainActor func testDisabled() {
        Global.autoOkuri = false
        XCTAssertEqual(Global.conversion.candidates(yomi: "かく", inputMode: .hiragana).map(\.word),
                       ["各", "角", "格", "核", "画", "確", "閣"])
    }

    @MainActor func testDirectMode() {
        XCTAssertEqual(Global.conversion.candidates(yomi: "かく", inputMode: .direct).map(\.word),
                       ["各", "角", "格", "核", "画", "確", "閣"])
    }
}
