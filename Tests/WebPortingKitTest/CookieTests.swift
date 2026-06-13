import Foundation
import NIOHTTP1
import Testing
@testable import WebPortingKit

@Suite("Cookie handling")
struct CookieTests {
    @Test("request cookies are parsed from all Cookie headers")
    func requestCookiesAreParsedFromAllCookieHeaders() {
        var headers = HTTPHeaders()
        headers.add(name: "Cookie", value: "session=abc123; theme=light")
        headers.add(name: "Cookie", value: "flag=true")

        let cookies = getRequestCookies(headers: headers)

        #expect(cookies["session"] == "abc123")
        #expect(cookies["theme"] == "light")
        #expect(cookies["flag"] == "true")
    }

    @Test("request cookie parser trims whitespace and unquotes quoted values")
    func requestCookieParserTrimsWhitespaceAndUnquotesQuotedValues() {
        let headers = HTTPHeaders([
            ("Cookie", "session = abc123 ; quoted=\"hello world\"; empty=")
        ])

        let cookies = getRequestCookies(headers: headers)

        #expect(cookies["session"] == "abc123")
        #expect(cookies["quoted"] == "hello world")
        #expect(cookies["empty"] == "")
    }

    @Test("request cookie parser ignores invalid pairs")
    func requestCookieParserIgnoresInvalidPairs() {
        let headers = HTTPHeaders([
            ("Cookie", "valid=ok; missing-value; bad name=value; =missing-name")
        ])

        let cookies = getRequestCookies(headers: headers)

        #expect(cookies == ["valid": "ok"])
    }

    @Test("valid response cookie values are serialized unchanged")
    func validResponseCookieValuesAreSerializedUnchanged() {
        var headers = HTTPHeaders()

        headers.add(cookie: ResponseCookie(name: "message", value: "hello-world_123"))

        #expect(headers.first(name: "Set-Cookie") == "message=hello-world_123")
    }

    @Test("invalid response cookie values are not serialized")
    func invalidResponseCookieValuesAreNotSerialized() {
        var headers = HTTPHeaders()

        headers.add(cookie: ResponseCookie(name: "message", value: "hello world;admin"))

        #expect(headers.first(name: "Set-Cookie") == nil)
    }

    @Test("invalid response cookie names are not serialized")
    func invalidResponseCookieNamesAreNotSerialized() {
        var headers = HTTPHeaders()

        headers.add(cookie: ResponseCookie(name: "bad name", value: "value"))

        #expect(headers.first(name: "Set-Cookie") == nil)
    }

    @Test("partitioned response cookie option is serialized")
    func partitionedResponseCookieOptionIsSerialized() {
        var headers = HTTPHeaders()

        headers.add(cookie: ResponseCookie(name: "session", value: "abc", options: .secure, .partitioned))

        #expect(headers.first(name: "Set-Cookie") == "session=abc; Secure; Partitioned")
    }

    @Test("cookie options expose serialized strings")
    func cookieOptionsExposeSerializedStrings() {
        #expect(CookieOption.httpOnly.appendString == "; HttpOnly")
        #expect(CookieOption.secure.appendString == "; Secure")
        #expect(CookieOption.sameSite(.strict).appendString == "; SameSite=Strict")
        #expect(CookieOption.partitioned.appendString == "; Partitioned")
    }

    @Test("cookie option array serializes in order")
    func cookieOptionArraySerializesInOrder() {
        let options: [CookieOption] = [.path("/"), .maxAge(10), .sameSite(.lax), .secure]

        #expect(options.appendString == "; Path=/; Max-Age=10; SameSite=Lax; Secure")
    }

    @Test("HTTP date helpers round trip rounded dates")
    func httpDateHelpersRoundTripRoundedDates() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000.9)
        let formatted = httpDateString(from: date)

        #expect(formatted == "Tue, 14 Nov 2023 22:13:20 GMT")
        #expect(try #require(httpDate(from: formatted)) == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("expires response cookie uses HTTP date formatting")
    func expiresResponseCookieUsesHTTPDateFormatting() {
        var headers = HTTPHeaders()
        let date = Date(timeIntervalSince1970: 1_700_000_000.9)

        headers.add(cookie: ResponseCookie(name: "session", value: "abc", options: .expires(date)))

        #expect(headers.first(name: "Set-Cookie") == "session=abc; Expires=\(httpDateString(from: date))")
    }

    @Test("negative max age is clamped to zero")
    func negativeMaxAgeIsClampedToZero() {
        var headers = HTTPHeaders()

        headers.add(cookie: ResponseCookie(name: "expired", value: "yes", options: .maxAge(-5)))

        #expect(headers.first(name: "Set-Cookie") == "expired=yes; Max-Age=0")
    }

    @Test("response cookie options reject header injection")
    func responseCookieOptionsRejectHeaderInjection() {
        var headers = HTTPHeaders()

        headers.add(cookie: ResponseCookie(name: "session", value: "abc", options: .path("/\r\nSet-Cookie: injected=true")))

        #expect(headers.first(name: "Set-Cookie") == nil)
    }
}
