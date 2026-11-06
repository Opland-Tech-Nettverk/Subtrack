// Checks the share extension's activation rule (SubtrackShare/Info.plist) the way the system reads it.
//
// The rule is an NSPredicate over the shared items. This script parses the exact string from the plist and
// evaluates it against mock items, so a typo (or someone putting back TRUEPREDICATE) fails CI instead of
// showing up as an extension that never appears, or one that appears for every file.
//
// Usage: swift scripts/check-share-activation-rule.swift SubtrackShare/Info.plist
import Foundation

final class Attachment: NSObject {
    @objc let registeredTypeIdentifiers: [String]
    init(_ identifiers: [String]) { registeredTypeIdentifiers = identifiers }
}

final class Item: NSObject {
    @objc let attachments: [Attachment]
    init(_ attachments: [[String]]) { self.attachments = attachments.map(Attachment.init) }
}

final class Root: NSObject {
    @objc let extensionItems: [Item]
    init(_ items: [[[String]]]) { extensionItems = items.map(Item.init) }
}

guard CommandLine.arguments.count == 2,
      let plist = NSDictionary(contentsOfFile: CommandLine.arguments[1]),
      let extensionInfo = plist["NSExtension"] as? [String: Any],
      let attributes = extensionInfo["NSExtensionAttributes"] as? [String: Any],
      let rule = attributes["NSExtensionActivationRule"] as? String
else {
    print("error: no NSExtensionActivationRule string found in the plist")
    exit(1)
}

if rule.uppercased().contains("TRUEPREDICATE") {
    print("error: the activation rule must not be TRUEPREDICATE")
    exit(1)
}

let predicate = NSPredicate(format: rule)

let text = "public.utf8-plain-text"
let pdf = "com.adobe.pdf"
let jpeg = "public.jpeg"
let png = "public.png"
let heic = "public.heic"

// (description, shared items, expected)
let cases: [(String, [[[String]]], Bool)] = [
    ("plain text", [[[text]]], true),
    ("pdf", [[[pdf]]], true),
    ("jpeg", [[[jpeg]]], true),
    ("png", [[[png]]], true),
    ("image with several representations", [[[heic, jpeg]]], true),
    ("text and one image", [[[text], [jpeg]]], true),
    ("text and one pdf", [[[text], [pdf]]], true),
    ("pdf and one image", [[[pdf], [png]]], true),
    ("two pdfs", [[[pdf], [pdf]]], false),
    ("two images", [[[jpeg], [png]]], false),
    ("zip", [[["public.zip-archive"]]], false),
    ("word document", [[["org.openxmlformats.wordprocessingml.document"]]], false),
    ("web page url", [[["public.url"]]], false),
    ("text with url (shared web page)", [[[text], ["public.url"]]], false),
    ("pdf with a zip", [[[pdf], ["public.zip-archive"]]], false),
    ("movie", [[["public.movie"]]], false),
    ("no attachments", [[]], false),
    ("no items", [], false),
    ("two items", [[[pdf]], [[pdf]]], false)
]

var failures = 0
for (name, items, expected) in cases {
    let actual = predicate.evaluate(with: Root(items))
    let ok = actual == expected
    print("\(ok ? "ok  " : "FAIL") \(name): expected \(expected), got \(actual)")
    if !ok { failures += 1 }
}
if failures > 0 {
    print("error: \(failures) case(s) failed")
    exit(1)
}
print("Activation rule OK (\(cases.count) cases)")
