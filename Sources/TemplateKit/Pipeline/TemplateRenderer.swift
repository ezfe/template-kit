/// Renders raw template data (bytes) to `View`s.
///
/// `TemplateRenderer`s combine a generic `TemplateParser` with the `TemplateSerializer` class to serialize templates.
///
///  - `TemplateParser`: parses the template data into an AST.
///  - `TemplateSerializer`: serializes the AST into a view.
///
/// The `TemplateRenderer` is expected to provide a `TemplateParser` that parses its specific templating language.
/// The `templateFileEnding` should also be unique to that templating language.
///
/// See each protocol requirement for more information.
public protocol TemplateRenderer: class {
    /// The available tags. `TemplateTag`s found in the AST will be looked up using this dictionary.
    var tags: [String: TagRenderer] { get }

    /// The renderer's `Container`. This is passed to all `TagContext` created during serializatin.
    var container: Container { get }

    /// Parses the template bytes into an AST.
    /// See `TemplateParser`.
    var parser: TemplateParser { get }

    /// Used to cache parsed ASTs for performance. If `nil`, caching will be skipped (useful for development modes).
    var astCache: ASTCache? { get set }

    /// The specific template file ending. This will be appended automatically when embedding views.
    var templateFileEnding: String { get }

    /// Relative leading directory for none absolute paths.
    var relativeDirectory: String { get }
}

extension TemplateRenderer {
    // MARK: Render

    /// Renders template bytes into a view using the supplied context.
    ///
    /// - parameters:
    ///     - template: Raw template bytes.
    ///     - context: `TemplateData` to expose as context to the template.
    ///     - file: Template description, will be used for generating errors.
    /// - returns: `Future` containing the rendered `View`.
    public func render(template: Data, _ context: TemplateData, file: String = "template") -> Future<View> {
        return Future.flatMap(on: container) {
            let hash = template.hashValue
            let ast: [TemplateSyntax]
            if let cached = self.astCache?.storage[hash] {
                ast = cached
            } else {
                let scanner = TemplateByteScanner(data: template, file: file)
                ast = try self.parser.parse(scanner: scanner)
                self.astCache?.storage[hash] = ast
            }

            let serializer = TemplateSerializer(
                renderer: self,
                context: .init(data: context),
                using: self.container
            )
            return serializer.serialize(ast: ast)
        }
    }

    // MARK: Convenience.

    /// Loads and renders a raw template at the supplied path.
    ///
    /// - parameters:
    ///     - path: Path to file contianing raw template bytes.
    ///     - context: `TemplateData` to expose as context to the template.
    /// - returns: `Future` containing the rendered `View`.
    public func render(_ path: String, _ context: TemplateData) -> Future<View> {
        let path = path.hasSuffix(templateFileEnding) ? path : path + templateFileEnding
        let absolutePath = path.hasPrefix("/") ? path : relativeDirectory + path

        guard let data = FileManager.default.contents(atPath: absolutePath) else {
            let error = TemplateKitError(
                identifier: "fileNotFound",
                reason: "No file was found at path: \(absolutePath)"
            )
            return Future.map(on: container) { throw error }
        }

        return render(template: data, context, file: absolutePath)
    }

    /// Loads and renders a raw template at the supplied path using an empty context.
    ///
    /// - parameters:
    ///     - path: Path to file contianing raw template bytes.
    /// - returns: `Future` containing the rendered `View`.
    public func render(_ path: String) -> Future<View> {
        return render(path, .null)
    }

    // MARK: Codable

    /// Renders the template bytes into a view using the supplied `Encodable` object as context.
    ///
    /// - parameters:
    ///     - template: Raw template bytes.
    ///     - context: `Encodable` item that will be encoded to `TemplateData` and used as template context.
    /// - returns: `Future` containing the rendered `View`.
    public func render<E>(template: Data, _ context: E) -> Future<View> where E: Encodable {
        return Future.flatMap(on: container) {
            return try TemplateDataEncoder().encode(context, on: self.container).flatMap(to: View.self) { context in
                return self.render(template: template, context)
            }
        }
    }

    /// Renders the template bytes into a view using the supplied `Encodable` object as context.
    ///
    /// - parameters:
    ///     - path: Path to file contianing raw template bytes.
    ///     - context: `Encodable` item that will be encoded to `TemplateData` and used as template context.
    /// - returns: `Future` containing the rendered `View`.
    public func render<E>(_ path: String, _ context: E) -> Future<View> where E: Encodable {
        return Future.flatMap(on: container) {
            return try TemplateDataEncoder().encode(context, on: self.container).flatMap(to: View.self) { context in
                return self.render(path, context)
            }
        }
    }
}
