import XCTest
@testable import TonePilotCore

final class MIDIParserTests: XCTestCase {
    func testParsesNoteOnOffAndRunningStatus() {
        var p = MIDIByteParser()
        // Note on C4, running-status note on E4, then velocity-0 note off for C4.
        let events = p.parse([0x90, 60, 100, 64, 90, 60, 0])
        XCTAssertEqual(events, [
            .noteOn(channel: 1, note: 60, velocity: 100),
            .noteOn(channel: 1, note: 64, velocity: 90),
            .noteOff(channel: 1, note: 60, velocity: 64),
        ])
    }

    func testIgnoresActiveSensingAndClockMidMessage() {
        var p = MIDIByteParser()
        let events = p.parse([0x91, 0xFE, 62, 0xF8, 80])
        XCTAssertEqual(events, [.noteOn(channel: 2, note: 62, velocity: 80)])
    }

    func testMessagesSplitAcrossPackets() {
        var p = MIDIByteParser()
        XCTAssertEqual(p.parse([0xB0, 64]), [])
        XCTAssertEqual(p.parse([127]), [.controlChange(channel: 1, controller: 64, value: 127)])
    }

    func testSkipsSysEx() {
        var p = MIDIByteParser()
        let events = p.parse([0xF0, 0x44, 0x01, 0x02, 0xF7, 0x80, 60, 0])
        XCTAssertEqual(events, [.noteOff(channel: 1, note: 60, velocity: 0)])
    }

    func testPitchBendAndProgramChange() {
        var p = MIDIByteParser()
        XCTAssertEqual(p.parse([0xE0, 0x00, 0x40, 0xC3, 5]),
                       [.pitchBend(channel: 1, value: 8192), .programChange(channel: 4, program: 5)])
    }

    func testUMPMidi1ChannelVoice() {
        XCTAssertEqual(MIDIByteParser.parseUMP(0x2090_3C64), .noteOn(channel: 1, note: 60, velocity: 100))
        XCTAssertEqual(MIDIByteParser.parseUMP(0x2090_3C00), .noteOff(channel: 1, note: 60, velocity: 64))
        XCTAssertNil(MIDIByteParser.parseUMP(0x1000_FE00), "system real-time UMP is not a channel voice message")
    }

    func testUMPWordStreamSkipsMultiWordMessages() {
        // note on, 2-word SysEx7 packet, note off
        let words: [UInt32] = [0x2090_3C64, 0x3001_7E00, 0x0000_0000, 0x2080_3C40]
        XCTAssertEqual(MIDIByteParser.parseUMPWords(words), [
            .noteOn(channel: 1, note: 60, velocity: 100), .noteOff(channel: 1, note: 60, velocity: 64),
        ])
    }
}

final class NoteRouterTests: XCTestCase {
    private func starts(_ c: [SoundCommand]) -> [UInt8] {
        c.compactMap { if case let .start(_, n, _) = $0 { return n } else { return nil } }
    }

    private func stops(_ c: [SoundCommand]) -> [UInt8] {
        c.compactMap { if case let .stop(_, n) = $0 { return n } else { return nil } }
    }

    func testLayersStackOnSameKeyWithOctaveShift() {
        let piano = Layer(patchId: UUID()), bell = Layer(patchId: UUID(), octave: 1)
        let r = NoteRouter()
        r.setArrangement(Arrangement(name: "a", layers: [piano, bell]))
        XCTAssertEqual(starts(r.handle(.noteOn(channel: 1, note: 60, velocity: 100))), [60, 72])
        XCTAssertEqual(stops(r.handle(.noteOff(channel: 1, note: 60, velocity: 0))), [60, 72])
        XCTAssertEqual(r.heldNoteCount, 0)
    }

    func testKeyboardSplitAndVelocityRange() {
        let bass = Layer(patchId: UUID(), keyRange: KeyRange(low: 0, high: 54))
        let soft = Layer(patchId: UUID(), keyRange: KeyRange(low: 55, high: 127), velocityRange: VelocityRange(low: 1, high: 80))
        let hard = Layer(patchId: UUID(), transpose: 12, keyRange: KeyRange(low: 55, high: 127), velocityRange: VelocityRange(low: 81, high: 127))
        let r = NoteRouter()
        r.setArrangement(Arrangement(name: "split", layers: [bass, soft, hard]))
        XCTAssertEqual(starts(r.handle(.noteOn(channel: 1, note: 40, velocity: 100))), [40])
        XCTAssertEqual(starts(r.handle(.noteOn(channel: 1, note: 60, velocity: 50))), [60])
        XCTAssertEqual(starts(r.handle(.noteOn(channel: 1, note: 62, velocity: 120))), [74])
    }

    func testNoteOffReleasesOriginalNoteAfterTransposeChange() {
        var layer = Layer(patchId: UUID(), transpose: 2)
        let r = NoteRouter()
        r.setArrangement(Arrangement(name: "a", layers: [layer]))
        XCTAssertEqual(starts(r.handle(.noteOn(channel: 1, note: 60, velocity: 100))), [62])
        layer.transpose = 5
        XCTAssertEqual(r.setArrangement(Arrangement(name: "a", layers: [layer])), [], "same layer stays held")
        XCTAssertEqual(stops(r.handle(.noteOff(channel: 1, note: 60, velocity: 0))), [62], "no stuck note")
    }

    func testSwitchingArrangementReleasesRemovedLayers() {
        let a = Layer(patchId: UUID()), b = Layer(patchId: UUID())
        let r = NoteRouter()
        r.setArrangement(Arrangement(name: "1", layers: [a]))
        _ = r.handle(.noteOn(channel: 1, note: 60, velocity: 100))
        let cmds = r.setArrangement(Arrangement(name: "2", layers: [b]))
        XCTAssertEqual(cmds, [.stop(layerId: a.id, note: 60)])
        XCTAssertEqual(r.handle(.noteOff(channel: 1, note: 60, velocity: 0)), [])
    }

    func testSharedOutputNoteIsReferenceCounted() {
        // Two channels (e.g. Casio main + split) play the same note on one omni layer.
        let l = Layer(patchId: UUID())
        let r = NoteRouter()
        r.setArrangement(Arrangement(name: "a", layers: [l]))
        _ = r.handle(.noteOn(channel: 1, note: 60, velocity: 100))
        _ = r.handle(.noteOn(channel: 2, note: 60, velocity: 100))
        XCTAssertEqual(stops(r.handle(.noteOff(channel: 1, note: 60, velocity: 0))), [], "other channel still holds it")
        XCTAssertEqual(stops(r.handle(.noteOff(channel: 2, note: 60, velocity: 0))), [60])
    }

    func testRetriggerWithoutNoteOffDoesNotLeak() {
        let l = Layer(patchId: UUID())
        let r = NoteRouter()
        r.setArrangement(Arrangement(name: "a", layers: [l]))
        _ = r.handle(.noteOn(channel: 1, note: 60, velocity: 100))
        let again = r.handle(.noteOn(channel: 1, note: 60, velocity: 100))
        XCTAssertEqual(stops(again), [60])
        XCTAssertEqual(starts(again), [60])
        XCTAssertEqual(stops(r.handle(.noteOff(channel: 1, note: 60, velocity: 0))), [60])
    }

    func testSustainForwardedAndPanicClearsState() {
        let l = Layer(patchId: UUID())
        let r = NoteRouter()
        r.setArrangement(Arrangement(name: "a", layers: [l]))
        XCTAssertEqual(r.handle(.controlChange(channel: 1, controller: 64, value: 127)), [.sustain(layerId: l.id, on: true)])
        _ = r.handle(.noteOn(channel: 1, note: 60, velocity: 100))
        let panic = r.panic()
        XCTAssertEqual(panic.first, .allNotesOff)
        XCTAssertTrue(panic.contains(.sustain(layerId: l.id, on: false)))
        XCTAssertEqual(r.heldNoteCount, 0)
        XCTAssertEqual(r.handle(.controlChange(channel: 1, controller: 123, value: 0)).first, .allNotesOff)
    }

    func testChannelFilterAndOutOfRangeNotes() {
        let ch2 = Layer(patchId: UUID(), midiChannel: 2)
        let high = Layer(patchId: UUID(), octave: 3)
        let r = NoteRouter()
        r.setArrangement(Arrangement(name: "a", layers: [ch2, high]))
        XCTAssertEqual(starts(r.handle(.noteOn(channel: 1, note: 100, velocity: 100))), [], "ch2 ignores ch1, 136 is out of range")
        XCTAssertEqual(starts(r.handle(.noteOn(channel: 2, note: 60, velocity: 100))), [60, 96])
    }

    func testVelocityCurves() {
        XCTAssertEqual(VelocityCurve.linear.apply(64), 64)
        XCTAssertGreaterThan(VelocityCurve.soft.apply(40), 40)
        XCTAssertLessThan(VelocityCurve.hard.apply(40), 40)
        XCTAssertEqual(VelocityCurve.fixed.apply(5), 100)
        XCTAssertEqual(VelocityCurve.hard.apply(1), 1, "never turns a note-on into a note-off")
    }
}
