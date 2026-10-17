import Foundation
import Testing
@testable import Subtrack

struct CancelLinkTests {

    @Test(arguments: [
        ("https://www.netflix.com/cancelplan", "https://www.netflix.com/cancelplan"),
        ("netflix.com/cancel", "https://netflix.com/cancel"),
        ("  spotify.com/account  ", "https://spotify.com/account"),
        ("http://example.no", "http://example.no")
    ])
    func acceptsValidLinks(input: String, expected: String) {
        #expect(CancelLink.url(from: input)?.absoluteString == expected)
    }

    @Test(arguments: ["", "   ", "netflix", "ikke en lenke", "ftp://example.com", "mailto:hei@example.com", ".com", "example."])
    func rejectsInvalidLinks(input: String) {
        #expect(CancelLink.url(from: input) == nil)
    }
}
