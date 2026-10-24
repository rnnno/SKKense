// SPDX-FileCopyrightText: 2026 mtgto <hogerappa@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// 変換候補の生成。辞書引き → 送り仮名の自動解決 →（将来）文脈による並べ替え を直列に行う。
@MainActor struct ConversionPipeline {
    func candidates(yomi: String, inputMode: InputMode) -> [Candidate] {
        let yomi = yomi.replacing("う゛", with: "ゔ")
        let nashi = Global.dictionary.referDicts(yomi, option: nil)
        let canResolveOkuri = Global.autoOkuri
            && inputMode != .direct && yomi.count >= 2 && !yomi.contains(">")
        let canResolveStem = Global.stemConversion
            && inputMode != .direct && yomi.count >= 2 && !yomi.contains(">")
        guard canResolveOkuri || canResolveStem else {
            return nashi
        }

        let snapshot = Global.dictionary.snapshot()
        let resolver = OkuriResolver(yomi: yomi)
        let splits = canResolveOkuri ? resolver.candidates(snapshot: snapshot) : []
        let stems: (user: [Candidate], dictionaries: [Candidate]) = canResolveStem
            ? StemResolver(yomi: yomi).candidates(snapshot: snapshot)
            : (user: [], dictionaries: [])
        var existingWords = Set(nashi.map(\.word))
        existingWords.formUnion(splits.map(\.word))
        let userStems = stems.user.filter { !existingWords.contains($0.word) }
        let dictionaryStems = stems.dictionaries.filter { !existingWords.contains($0.word) }
        return resolver.merge(nashi: nashi,
                              splits: splits,
                              userStems: userStems,
                              dictionaryStems: dictionaryStems,
                              snapshot: snapshot)
    }

    func candidates(midashi: String, okuri: String, reading: String, inputMode: InputMode) -> [Candidate] {
        let midashi = midashi.replacing("う゛", with: "ゔ")
        let okuri = okuri.replacing("う゛", with: "ゔ")
        var candidates = Global.dictionary.referDicts(midashi, option: .okuri(okuri))
        let reading = reading.replacing("う゛", with: "ゔ")
        guard Global.stemConversion, inputMode != .direct, reading.count >= 2 else {
            return candidates
        }

        let stems = StemResolver(yomi: reading).candidates(snapshot: Global.dictionary.snapshot())
        var seen = Set(candidates.map(\.word))
        for candidate in stems.user + stems.dictionaries where seen.insert(candidate.word).inserted {
            candidates.append(candidate)
        }
        return candidates
    }
}

extension Global {
    @MainActor static var conversion: ConversionPipeline { ConversionPipeline() }
}

struct OkuriResolver {
    static let allowedTails: Set<String> = [
        "", "る", "た", "て", "ない", "なかった", "ます", "ました", "ません", "ましょう",
        "い", "く", "かった", "くて", "ければ", "れば", "よう", "れ", "ろ", "ん", "ぬ", "ず",
        "き", "け", "こ", "さ", "し", "す", "せ", "そ", "う", "え", "お", "った", "って",
        "たい", "たら", "たり", "れる", "られる", "せる", "させる", "ている", "てる", "しい",
        "しかった", "しく", "しくて", "しければ",
    ]
    static let nashiHeadCount = 3
    static let splitHeadCount = 3

    let yomi: String

    static func letters(for kana: Character) -> [String] {
        guard let first = Romaji.firstRomajis[kana] else { return [] }
        var letters = [String(first)]
        let alias: String? = switch kana {
        case "ち": "c"
        case "じ": "z"
        case "ふ": "f"
        default: nil
        }
        if let alias, !letters.contains(alias) {
            letters.append(alias)
        }
        return letters
    }

    func candidates(snapshot: UserDict.Snapshot) -> [Candidate] {
        let characters = Array(yomi)
        var results: [Candidate] = []
        var seen = Set<String>()

        for index in stride(from: characters.count - 1, through: 1, by: -1) {
            let stem = String(characters[..<index])
            let okuri = String(characters[index...])
            guard Self.allowedTails.contains(String(okuri.dropFirst())),
                  let firstKana = okuri.first else {
                continue
            }
            let okuriBlock = String(firstKana)
            for letter in Self.letters(for: firstKana) {
                let midashi = stem + letter
                let candidates = snapshot.referDicts(midashi,
                                                     option: .okuri(okuriBlock),
                                                     findFromAllDicts: true)
                for candidate in candidates {
                    let word = candidate.candidateString + okuri
                    if seen.insert(word).inserted {
                        results.append(Candidate(word,
                                                 annotations: candidate.annotations,
                                                 original: Candidate.Original(midashi: midashi,
                                                                              word: candidate.candidateString,
                                                                              okuri: okuriBlock,
                                                                              usesOwnOkuri: true),
                                                 saveToUserDict: candidate.saveToUserDict))
                    }
                }
            }
        }
        return results
    }

    func merge(nashi: [Candidate],
               splits: [Candidate],
               userStems: [Candidate],
               dictionaryStems: [Candidate],
               snapshot: UserDict.Snapshot) -> [Candidate] {
        let userNashiWords = Set(snapshot.refer(yomi, option: nil).map(\.word))
        let userNashi = nashi.filter { userNashiWords.contains($0.candidateString) }
        let remainingNashi = nashi.filter { !userNashiWords.contains($0.candidateString) }
        let userSplits = splits.filter { candidate in
            guard let original = candidate.original, let okuri = original.okuri else { return false }
            return snapshot.refer(original.midashi, option: .okuri(okuri)).contains {
                $0.word == original.word
            }
        }
        let userSplitWords = Set(userSplits.map(\.word))
        let remainingSplits = splits.filter { !userSplitWords.contains($0.word) }

        var results: [Candidate] = []
        var seen = Set<String>()
        func append<S: Sequence>(_ candidates: S) where S.Element == Candidate {
            for candidate in candidates where seen.insert(candidate.word).inserted {
                results.append(candidate)
            }
        }

        append(userNashi)
        append(userSplits)
        append(userStems)
        append(remainingNashi.prefix(Self.nashiHeadCount))
        append(remainingSplits.prefix(Self.splitHeadCount))
        append(remainingNashi.dropFirst(Self.nashiHeadCount))
        append(remainingSplits.dropFirst(Self.splitHeadCount))
        append(dictionaryStems)
        return results
    }
}

struct StemResolver {
    let yomi: String

    func candidates(snapshot: UserDict.Snapshot) -> (user: [Candidate], dictionaries: [Candidate]) {
        var seen = Set<String>()
        let user: [Candidate]
        if !snapshot.privateMode || !snapshot.ignoreUserDictInPrivateMode, let userDict = snapshot.userDict {
            user = candidates(in: userDict, seen: &seen)
        } else {
            user = []
        }
        var dictionaries: [Candidate] = []
        for dict in snapshot.dicts {
            dictionaries.append(contentsOf: candidates(in: dict, seen: &seen))
        }
        return (user, dictionaries)
    }

    private func candidates(in dict: MemoryDict, seen: inout Set<String>) -> [Candidate] {
        let midashis = dict.okuriAriYomis.filter { midashi in
            guard midashi.hasPrefix(yomi),
                  midashi.count == yomi.count + 1,
                  let last = midashi.last else {
                return false
            }
            return "abcdefghijklmnopqrstuvwxyz".contains(last)
        }.sorted()

        var results: [Candidate] = []
        for midashi in midashis {
            for word in dict.refer(midashi, option: nil) where seen.insert(word.word).inserted {
                results.append(Candidate(word: word,
                                         original: Candidate.Original(midashi: midashi,
                                                                      word: word.word,
                                                                      usesOwnOkuri: true),
                                         saveToUserDict: dict.saveToUserDict))
            }
        }
        return results
    }
}
