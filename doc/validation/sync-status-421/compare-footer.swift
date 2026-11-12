import AppKit
import Foundation

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "doc/validation/sync-status-421")
let names = ["status-recovery-before-failure.png", "status-recovery-failed.png",
             "status-recovery-online.png", "status-approval-before.png", "status-approval-required.png"]
let images = names.map { name -> NSBitmapImageRep in
    guard let data = try? Data(contentsOf: root.appendingPathComponent(name)),
          let image = NSBitmapImageRep(data: data), image.pixelsWide == 1064, image.pixelsHigh == 520 else {
        fatalError("Missing or unexpected capture: \(name)")
    }
    return image
}
var failed = false
for (name, image) in zip(names, images) {
    var differences = 0
    for y in 330..<460 { for x in 20..<1000 {
        if image.colorAt(x: x, y: y) != images[0].colorAt(x: x, y: y) { differences += 1 }
    }}
    print("\(name): \(differences) different pixels in downstream control region")
    failed = failed || differences != 0
}
if failed { exit(1) }
