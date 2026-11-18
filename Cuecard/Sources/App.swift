import AppKit

@main
struct CuecardApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let cuecard = Cuecard()
        application.delegate = cuecard
        withExtendedLifetime(cuecard) { application.run() }
    }
}
