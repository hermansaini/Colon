import Foundation

enum CLDRAnnotationParser {
    static func parse(_ sourceFiles: [Data]) throws -> [String: CLDRAnnotation] {
        var merged: [String: CLDRAnnotation] = [:]

        for data in sourceFiles {
            let delegate = AnnotationParserDelegate()
            let parser = XMLParser(data: data)
            parser.delegate = delegate
            parser.shouldResolveExternalEntities = false

            guard parser.parse() else {
                throw EmojiDataGeneratorError.xmlParseFailed(
                    parser.parserError?.localizedDescription ?? "Unknown parser failure"
                )
            }

            for (emoji, annotation) in delegate.annotations {
                var existing = merged[emoji, default: CLDRAnnotation(name: nil, tags: [])]
                if existing.name == nil {
                    existing.name = annotation.name
                }
                existing.tags = stableUnique(existing.tags + annotation.tags)
                merged[emoji] = existing
            }
        }

        return merged
    }
}

private final class AnnotationParserDelegate: NSObject, XMLParserDelegate {
    private var currentEmoji: String?
    private var currentType: String?
    private var currentText = ""
    private var shouldCapture = false

    var annotations: [String: CLDRAnnotation] = [:]

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "annotation",
              attributeDict["alt"] == nil,
              let emoji = attributeDict["cp"]
        else {
            shouldCapture = false
            return
        }

        currentEmoji = emoji
        currentType = attributeDict["type"]
        currentText = ""
        shouldCapture = true
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if shouldCapture {
            currentText += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard elementName == "annotation", shouldCapture, let currentEmoji else {
            return
        }

        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        var annotation = annotations[currentEmoji, default: CLDRAnnotation(name: nil, tags: [])]

        if currentType == "tts" {
            annotation.name = value
        } else {
            annotation.tags = stableUnique(
                annotation.tags + value.split(separator: "|").map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            )
        }

        annotations[currentEmoji] = annotation
        shouldCapture = false
        self.currentEmoji = nil
        currentType = nil
        currentText = ""
    }
}
