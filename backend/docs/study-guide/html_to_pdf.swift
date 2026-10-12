// Renders an HTML file to PDF with the system's WebKit, and joins PDFs. No browser is launched.
//
//   html_to_pdf page portrait|landscape in.html out.pdf
//   html_to_pdf join out.pdf a.pdf b.pdf ...
//
// build_study_guide.py compiles and runs it.
//
// One HTML file a run: a second web view in the same process is killed by the system here.
import AppKit
import PDFKit
import WebKit

final class Renderer: NSObject, WKNavigationDelegate {
    let landscape: Bool
    let input: URL
    let output: URL
    var webView: WKWebView!
    var window: NSWindow!

    init(landscape: Bool, input: URL, output: URL) {
        self.landscape = landscape
        self.input = input
        self.output = output
    }

    var paper: NSSize { landscape ? NSSize(width: 841.89, height: 595.28) : NSSize(width: 595.28, height: 841.89) }

    func start() {
        webView = WKWebView(frame: NSRect(origin: .zero, size: paper))
        webView.navigationDelegate = self
        window = NSWindow(contentRect: NSRect(origin: .zero, size: paper), styleMask: [.borderless],
                          backing: .buffered, defer: false)
        window.contentView = webView
        webView.loadFileURL(input, allowingReadAccessTo: input.deletingLastPathComponent())
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let info = NSPrintInfo()
        info.paperSize = paper
        info.orientation = landscape ? .landscape : .portrait
        let margin: CGFloat = landscape ? 24 : 48
        info.topMargin = margin; info.bottomMargin = margin; info.leftMargin = margin - 4; info.rightMargin = margin - 4
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = output
        // Let layout and fonts settle before printing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let operation = webView.printOperation(with: info)
            operation.showsPrintPanel = false
            operation.showsProgressPanel = false
            operation.view?.frame = NSRect(origin: .zero, size: info.paperSize)
            operation.runModal(for: self.window, delegate: self,
                               didRun: #selector(self.printed(_:success:contextInfo:)), contextInfo: nil)
        }
    }

    @objc func printed(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        if !success { FileHandle.standardError.write(Data("printing \(input.lastPathComponent) failed\n".utf8)) }
        exit(success ? 0 : 1)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.count >= 3, arguments[0] == "join" {
    let merged = PDFDocument()
    for path in arguments.dropFirst(2) {
        guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else {
            FileHandle.standardError.write(Data("can't read \(path)\n".utf8)); exit(1)
        }
        for i in 0..<document.pageCount { merged.insert(document.page(at: i)!, at: merged.pageCount) }
    }
    merged.write(to: URL(fileURLWithPath: arguments[1]))
    print("wrote \(arguments[1]): \(merged.pageCount) pages")
    exit(0)
}
guard arguments.count == 4, arguments[0] == "page" else {
    print("usage: html_to_pdf page portrait|landscape in.html out.pdf | html_to_pdf join out.pdf a.pdf b.pdf ...")
    exit(2)
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let renderer = Renderer(landscape: arguments[1] == "landscape", input: URL(fileURLWithPath: arguments[2]),
                        output: URL(fileURLWithPath: arguments[3]))
DispatchQueue.main.async { renderer.start() }
app.run()
