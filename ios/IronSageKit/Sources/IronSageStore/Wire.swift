import Foundation
import IronSageAPI

/// Converts between the app's types (IronSageCore) and the generated API types through
/// JSON, and encodes what the store keeps on disk.
///
/// The generated types already use the API's snake_case keys; the app's types use
/// camelCase properties. Encoding converts keys to snake_case (which leaves keys that
/// are already snake_case alone), and decoding into an app type converts them back.
/// A field that exists on one side only is ignored, and a type mismatch throws, which
/// the store tests catch.
enum Wire {
    static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(try FlexibleISO8601DateTranscoder().encode(date))
        }
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    /// Decodes into one of the app's types.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder(convertingKeys: true).decode(type, from: data)
    }

    /// Generated API type → app type.
    static func app<T: Decodable>(_ value: some Encodable, as type: T.Type) throws -> T {
        try decode(type, from: encode(value))
    }

    /// App type → generated API type.
    static func api<T: Decodable>(_ value: some Encodable, as type: T.Type) throws -> T {
        try decoder(convertingKeys: false).decode(type, from: encode(value))
    }

    private static func decoder(convertingKeys: Bool) -> JSONDecoder {
        let decoder = JSONDecoder()
        if convertingKeys {
            decoder.keyDecodingStrategy = .convertFromSnakeCase
        }
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            return try FlexibleISO8601DateTranscoder().decode(string)
        }
        return decoder
    }
}
