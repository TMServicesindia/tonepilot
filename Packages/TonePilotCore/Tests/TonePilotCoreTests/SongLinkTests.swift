import XCTest
@testable import TonePilotCore

final class SongLinkTests: XCTestCase {
    func testRecognisesServices() {
        XCTAssertEqual(SongLink("https://www.youtube.com/watch?v=gB2zKZxESTg&list=RD")?.service, .youtube)
        XCTAssertEqual(SongLink("youtu.be/abc")?.service, .youtube)
        XCTAssertEqual(SongLink("https://music.youtube.com/watch?v=abc")?.service, .youtubeMusic)
        XCTAssertEqual(SongLink("https://open.spotify.com/track/123")?.service, .spotify)
        XCTAssertEqual(SongLink("https://www.jiosaavn.com/song/hukum/x")?.service, .jioSaavn)
        XCTAssertEqual(SongLink("https://music.apple.com/in/album/x")?.service, .appleMusic)
        XCTAssertNil(SongLink("not a link"))
        XCTAssertNil(SongLink("ftp://x.com/a"))
    }

    func testOEmbedEndpointsKeepTheWholeLink() throws {
        let link = try XCTUnwrap(SongLink("https://www.youtube.com/watch?v=gB2zKZxESTg&list=RDgB2zKZxESTg"))
        let url = try XCTUnwrap(link.oEmbedURL).absoluteString
        XCTAssertTrue(url.hasPrefix("https://www.youtube.com/oembed?format=json&url=https"))
        XCTAssertTrue(url.contains("%26list%3D"), "the video link's own & and = must be encoded: \(url)")
        XCTAssertNil(SongLink("https://www.jiosaavn.com/song/x")?.oEmbedURL)
    }

    func testParsesAndCleansTitles() {
        let json = #"{"title":"Hukum - Thalaivar Alappara | Jailer | Superstar Rajinikanth | Anirudh | Sun Pictures","author_name":"Sun TV"}"#
        let m = SongLink.parseOEmbed(Data(json.utf8))
        XCTAssertEqual(m?.title, "Hukum - Thalaivar Alappara")
        XCTAssertEqual(m?.author, "Sun TV")
        XCTAssertEqual(SongLink.cleanTitle("Kaavaalaa (Lyric Video) - Jailer"), "Kaavaalaa")
        XCTAssertNil(SongLink.parseOEmbed(Data("{}".utf8)))
    }
}
