import XCTest
@testable import Cinema

final class StremioAccountClientTests: XCTestCase {
    func testLoginSendsExpectedBodyAndReturnsAuthKey() async throws {
        let http = MockHTTPClient(json: """
        {"result": {"authKey": "secret-key", "user": {"_id": "u1", "email": "me@example.com"}}}
        """)
        let client = StremioAccountClient(http: http)

        let session = try await client.login(email: "me@example.com", password: "hunter2")

        XCTAssertEqual(session, StremioSession(authKey: "secret-key", email: "me@example.com"))
        let request = try XCTUnwrap(http.lastRequest)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.strem.io/api/login")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(request.jsonBody)
        XCTAssertEqual(body["type"] as? String, "Login")
        XCTAssertEqual(body["email"] as? String, "me@example.com")
        XCTAssertEqual(body["password"] as? String, "hunter2")
    }

    func testWrongPasswordIsReported() async {
        let http = MockHTTPClient(json: #"{"error": {"message": "Wrong passphrase", "code": 2}}"#)
        do {
            _ = try await StremioAccountClient(http: http).login(email: "a@b.c", password: "x")
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? StremioAccountError, .wrongCredentials)
        }
    }

    func testMissingAuthKeyIsAnError() async {
        let http = MockHTTPClient(json: #"{"result": {"user": {}}}"#)
        do {
            _ = try await StremioAccountClient(http: http).login(email: "a@b.c", password: "x")
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? StremioAccountError, .missingAuthKey)
        }
    }

    func testAddonCollectionParsing() async throws {
        let http = MockHTTPClient(json: """
        {"result": {"addons": [
          {"transportUrl": "https://v3-cinemeta.strem.io/manifest.json",
           "transportName": "",
           "manifest": \(Fixtures.cinemetaManifest),
           "flags": {"official": true, "protected": true}},
          {"transportUrl": "https://broken.example.com/manifest.json", "manifest": {"name": "no id"}},
          {"transportUrl": "https://streams.example.com/abc/manifest.json",
           "manifest": \(Fixtures.streamAddonManifest)}
        ], "lastModified": "2024-01-01T00:00:00.000Z"}}
        """)
        let client = StremioAccountClient(http: http)

        let addons = try await client.addonCollection(authKey: "secret-key")

        XCTAssertEqual(addons.map(\.manifest.id), ["com.linvo.cinemeta", "org.example.streams"])
        XCTAssertEqual(addons[0].flags?.official, true)
        XCTAssertEqual(addons[1].manifestURL?.host, "streams.example.com")

        let request = try XCTUnwrap(http.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://api.strem.io/api/addonCollectionGet")
        let body = try XCTUnwrap(request.jsonBody)
        XCTAssertEqual(body["type"] as? String, "AddonCollectionGet")
        XCTAssertEqual(body["authKey"] as? String, "secret-key")
        XCTAssertEqual(body["update"] as? Bool, true)
    }

    func testExpiredSession() async {
        let http = MockHTTPClient(status: 401, json: #"{"error": {"message": "Session does not exist", "code": 1}}"#)
        do {
            _ = try await StremioAccountClient(http: http).addonCollection(authKey: "old")
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? StremioAccountError, .sessionExpired)
        }
    }

    func testServerErrorWithoutEnvelope() async {
        let http = MockHTTPClient(status: 503, json: "Service Unavailable")
        do {
            _ = try await StremioAccountClient(http: http).addonCollection(authKey: "k")
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? StremioAccountError, .httpStatus(503))
        }
    }
}
