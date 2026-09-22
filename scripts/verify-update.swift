import Foundation
import CryptoKit

// Verification uses only the public key; it never requests Keychain access.
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw NSError(domain: "TintLinkRelease", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
guard CommandLine.arguments.count == 4 else { fatalError("Usage: verify-update.swift appcast.xml archive.zip public-key") }
let feed = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
guard let rawKey = Data(base64Encoded: CommandLine.arguments[3]) else { fatalError("Invalid public key") }
let key = try Curve25519.Signing.PublicKey(rawRepresentation: rawKey)
let marker = Data("<!-- sparkle-signatures:\n".utf8)
guard let range = feed.range(of: marker, options: .backwards),
      let trailer = String(data: feed[range.upperBound...], encoding: .utf8) else { fatalError("Feed signature missing") }
let fields = trailer.components(separatedBy: "\n")
guard fields.count >= 3, fields[0].hasPrefix("edSignature: "), fields[1].hasPrefix("length: "),
      let signature = Data(base64Encoded: String(fields[0].dropFirst(13))),
      let length = Int(fields[1].dropFirst(8)) else { fatalError("Invalid feed signature") }
try require(length == range.lowerBound, "Unexpected signed feed length")
let signedFeed = feed.prefix(length)
try require(key.isValidSignature(signature, for: signedFeed), "Feed signature verification failed")
let document = try XMLDocument(data: signedFeed, options: [])
let name = URL(fileURLWithPath: CommandLine.arguments[2]).lastPathComponent
let enclosures = try document.nodes(forXPath: "//enclosure").compactMap { $0 as? XMLElement }
guard let enclosure = enclosures.first(where: { URL(string: $0.attribute(forName: "url")?.stringValue ?? "")?.lastPathComponent == name }),
      let encoded = enclosure.attribute(forName: "sparkle:edSignature")?.stringValue,
      let archiveSignature = Data(base64Encoded: encoded) else { fatalError("Archive signature missing") }
try require(enclosure.attribute(forName: "length")?.stringValue == String(archive.count), "Archive size does not match the feed")
try require(key.isValidSignature(archiveSignature, for: archive), "Archive signature verification failed")
var tampered = archive
tampered[tampered.startIndex] ^= 1
try require(!key.isValidSignature(archiveSignature, for: tampered), "Tampered archive was accepted")
var tamperedFeed = Data(signedFeed)
tamperedFeed[tamperedFeed.startIndex] ^= 1
try require(!key.isValidSignature(signature, for: tamperedFeed), "Tampered feed was accepted")
print("Feed and archive signatures verified; modified feed/archive rejected")
