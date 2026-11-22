//
//  CubeLUTParser.swift
//  iRetro
//
//  Deployment Target: iOS 12.0+ (Supports iPhone 5S / Apple A7 / 1GB RAM)
//  Frameworks: Foundation, CoreImage, CoreGraphics
//

import Foundation
import CoreImage
import CoreGraphics

/// Errors thrown during `.cube` 3D LUT parsing and filter creation.
public enum CubeLUTError: LocalizedError {
    case fileNotFound(URL)
    case unreadableFile(String)
    case unsupported1DLUT
    case missingOrInvalidDimension
    case invalidDomainBounds
    case malformedRGBRow(line: Int, content: String)
    case dataCountMismatch(expected: Int, actual: Int)
    case filterCreationFailed

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File .cube tidak ditemukan di: \(url.lastPathComponent)"
        case .unreadableFile(let reason):
            return "Gagal membaca file .cube: \(reason)"
        case .unsupported1DLUT:
            return "Format 1D LUT tidak didukung. Gunakan file 3D LUT (.cube)."
        case .missingOrInvalidDimension:
            return "Header LUT_3D_SIZE tidak ditemukan atau di luar rentang valid (2...65)."
        case .invalidDomainBounds:
            return "Batas DOMAIN_MIN / DOMAIN_MAX pada file .cube tidak valid."
        case .malformedRGBRow(let line, let content):
            return "Baris RGB tidak valid pada baris \(line): '\(content)'"
        case .dataCountMismatch(let expected, let actual):
            return "Jumlah titik data 3D LUT tidak sesuai (ekspektasi: \(expected), ditemukan: \(actual))."
        case .filterCreationFailed:
            return "Gagal membuat filter CoreImage CIColorCube."
        }
    }
}

/// Representasi data 3D LUT yang telah diparsing dan siap dikonversi ke `CIColorCube`.
public struct ParsedCubeLUT {
    public let title: String?
    public let dimension: Int
    /// Premultiplied RGBA Float32 buffer (`dimension * dimension * dimension * 4` floats, atau `dimension^3 * 16` bytes).
    public let rgbaCubeData: Data
}

/// Parser performa tinggi & hemat memori untuk file teks `.cube` 3D LUT standar.
public final class CubeLUTParser {

    /// Color space sRGB bersama yang digunakan untuk konsistensi `CIColorCubeWithColorSpace`.
    private static let sRGBColorSpace: CGColorSpace = {
        return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }()

    // MARK: - Public API

    /// Membaca dan mem-parsing file `.cube` dari `URL` menjadi `ParsedCubeLUT`.
    /// Dirancang dengan `autoreleasepool` agar hemat RAM pada perangkat 1 GB (iPhone 5S).
    public static func parse(fileURL: URL) throws -> ParsedCubeLUT {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw CubeLUTError.fileNotFound(fileURL)
        }

        let content: String
        do {
            content = try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            do {
                content = try String(contentsOf: fileURL, encoding: .ascii)
            } catch {
                throw CubeLUTError.unreadableFile(error.localizedDescription)
            }
        }

        return try parse(cubeString: content, fallbackTitle: fileURL.deletingPathExtension().lastPathComponent)
    }

    /// Mem-parsing string isi file `.cube`, melewati komentar (`#`), dan mengekstrak matriks 3D RGB
    /// langsung menjadi buffer RGBA Float32 untuk `CIColorCube`.
    public static func parse(cubeString: String, fallbackTitle: String? = nil) throws -> ParsedCubeLUT {
        var title: String? = fallbackTitle
        var dimension: Int = 0
        var domainMin: (Float, Float, Float) = (0.0, 0.0, 0.0)
        var domainMax: (Float, Float, Float) = (1.0, 1.0, 1.0)

        // Array RGBA Float32 dialokasikan secara tepat segera setelah LUT_3D_SIZE ditemukan
        var rgbaFloats: ContiguousArray<Float> = []
        var expectedPoints = 0
        var parsedPoints = 0
        var lineNumber = 0

        var parseError: CubeLUTError?

        cubeString.enumerateLines { rawLine, stop in
            lineNumber += 1

            // Pangkas spasi/tab di awal dan akhir baris
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") {
                return
            }

            // Buang inline comment jika ada tanda '#' di tengah baris (kecuali di dalam TITLE)
            let effectiveLine: String
            if !line.uppercased().hasPrefix("TITLE"), let hashIndex = line.firstIndex(of: "#") {
                effectiveLine = String(line[..<hashIndex]).trimmingCharacters(in: .whitespaces)
                if effectiveLine.isEmpty { return }
            } else {
                effectiveLine = line
            }

            let upper = effectiveLine.uppercased()

            // 1. Header Metadata
            if upper.hasPrefix("TITLE") {
                if let firstQuote = effectiveLine.firstIndex(of: "\""),
                   let lastQuote = effectiveLine.lastIndex(of: "\""),
                   firstQuote < lastQuote {
                    let start = effectiveLine.index(after: firstQuote)
                    title = String(effectiveLine[start..<lastQuote])
                } else {
                    let parts = effectiveLine.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
                    if parts.count == 2 {
                        title = String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
                    }
                }
                return
            }

            if upper.hasPrefix("LUT_1D_SIZE") {
                parseError = .unsupported1DLUT
                stop = true
                return
            }

            if upper.hasPrefix("LUT_3D_SIZE") {
                let tokens = effectiveLine.split(whereSeparator: { $0 == " " || $0 == "\t" })
                guard tokens.count >= 2, let size = Int(tokens[1]), (2...65).contains(size) else {
                    parseError = .missingOrInvalidDimension
                    stop = true
                    return
                }
                dimension = size
                expectedPoints = size * size * size
                rgbaFloats.reserveCapacity(expectedPoints * 4)
                return
            }

            if upper.hasPrefix("DOMAIN_MIN") {
                guard let rgb = parseThreeFloats(from: effectiveLine, dropFirstToken: true) else {
                    parseError = .invalidDomainBounds
                    stop = true
                    return
                }
                domainMin = rgb
                return
            }

            if upper.hasPrefix("DOMAIN_MAX") {
                guard let rgb = parseThreeFloats(from: effectiveLine, dropFirstToken: true) else {
                    parseError = .invalidDomainBounds
                    stop = true
                    return
                }
                domainMax = rgb
                return
            }

            if upper.hasPrefix("LUT_3D_INPUT_RANGE") {
                let tokens = effectiveLine.split(whereSeparator: { $0 == " " || $0 == "\t" })
                if tokens.count >= 3, let minVal = Float(tokens[1]), let maxVal = Float(tokens[2]) {
                    domainMin = (minVal, minVal, minVal)
                    domainMax = (maxVal, maxVal, maxVal)
                }
                return
            }

            // 2. Baris Data RGB
            guard dimension > 0 else {
                // Abaikan token header tak dikenal sebelum LUT_3D_SIZE, atau laporkan error jika berupa angka
                if parseThreeFloats(from: effectiveLine, dropFirstToken: false) != nil {
                    parseError = .missingOrInvalidDimension
                    stop = true
                }
                return
            }

            guard let (rawR, rawG, rawB) = parseThreeFloats(from: effectiveLine, dropFirstToken: false) else {
                parseError = .malformedRGBRow(line: lineNumber, content: effectiveLine)
                stop = true
                return
            }

            let rangeR = domainMax.0 - domainMin.0
            let rangeG = domainMax.1 - domainMin.1
            let rangeB = domainMax.2 - domainMin.2

            guard rangeR > 0, rangeG > 0, rangeB > 0 else {
                parseError = .invalidDomainBounds
                stop = true
                return
            }

            // Normalisasi dan clamp ke [0.0, 1.0] untuk premultiplied RGBA CoreImage
            let r = min(max((rawR - domainMin.0) / rangeR, 0.0), 1.0)
            let g = min(max((rawG - domainMin.1) / rangeG, 0.0), 1.0)
            let b = min(max((rawB - domainMin.2) / rangeB, 0.0), 1.0)

            rgbaFloats.append(r)
            rgbaFloats.append(g)
            rgbaFloats.append(b)
            rgbaFloats.append(1.0) // Alpha = 1.0 (premultiplied)

            parsedPoints += 1
        }

        if let error = parseError {
            throw error
        }

        guard dimension >= 2 else {
            throw CubeLUTError.missingOrInvalidDimension
        }

        guard parsedPoints == expectedPoints else {
            throw CubeLUTError.dataCountMismatch(expected: expectedPoints, actual: parsedPoints)
        }

        let cubeData = rgbaFloats.withUnsafeBufferPointer { bufferPointer -> Data in
            return Data(buffer: bufferPointer)
        }

        return ParsedCubeLUT(title: title, dimension: dimension, rgbaCubeData: cubeData)
    }

    /// Mengonversi array float 3D RGB (`N * N * N * 3`) menjadi filter `CIColorCubeWithColorSpace` (atau fallback `CIColorCube`).
    public static func makeColorCubeFilter(fromRGBFloats rgbFloats: [Float], dimension: Int) throws -> CIFilter {
        let expectedRGBCount = dimension * dimension * dimension * 3
        guard dimension >= 2, rgbFloats.count == expectedRGBCount else {
            throw CubeLUTError.dataCountMismatch(expected: expectedRGBCount / 3, actual: rgbFloats.count / 3)
        }

        var rgbaFloats = ContiguousArray<Float>()
        rgbaFloats.reserveCapacity(dimension * dimension * dimension * 4)

        var idx = 0
        while idx < expectedRGBCount {
            let r = min(max(rgbFloats[idx], 0.0), 1.0)
            let g = min(max(rgbFloats[idx + 1], 0.0), 1.0)
            let b = min(max(rgbFloats[idx + 2], 0.0), 1.0)
            rgbaFloats.append(r)
            rgbaFloats.append(g)
            rgbaFloats.append(b)
            rgbaFloats.append(1.0)
            idx += 3
        }

        let data = rgbaFloats.withUnsafeBufferPointer { Data(buffer: $0) }
        return try makeColorCubeFilter(fromPremultipliedRGBAData: data, dimension: dimension)
    }

    /// Membuat filter `CIColorCubeWithColorSpace` (atau `CIColorCube`) dari `Data` RGBA Float32.
    public static func makeColorCubeFilter(fromPremultipliedRGBAData cubeData: Data, dimension: Int) throws -> CIFilter {
        let expectedByteCount = dimension * dimension * dimension * 4 * MemoryLayout<Float>.size
        guard dimension >= 2, cubeData.count == expectedByteCount else {
            throw CubeLUTError.filterCreationFailed
        }

        if let filter = CIFilter(name: "CIColorCubeWithColorSpace") {
            filter.setValue(dimension, forKey: "inputCubeDimension")
            filter.setValue(cubeData, forKey: "inputCubeData")
            filter.setValue(sRGBColorSpace, forKey: "inputColorSpace")
            return filter
        } else if let fallbackFilter = CIFilter(name: "CIColorCube") {
            fallbackFilter.setValue(dimension, forKey: "inputCubeDimension")
            fallbackFilter.setValue(cubeData, forKey: "inputCubeData")
            return fallbackFilter
        }

        throw CubeLUTError.filterCreationFailed
    }

    // MARK: - Private Fast Float Tokenizer

    /// Mengekstrak 3 nilai `Float` dari satu baris teks tanpa alokasi RegEx.
    private static func parseThreeFloats(from line: String, dropFirstToken: Bool) -> (Float, Float, Float)? {
        let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        let startIndex = dropFirstToken ? 1 : 0
        guard tokens.count >= startIndex + 3 else { return nil }

        guard let f0 = Float(tokens[startIndex]),
              let f1 = Float(tokens[startIndex + 1]),
              let f2 = Float(tokens[startIndex + 2]),
              f0.isFinite, f1.isFinite, f2.isFinite else {
            return nil
        }
        return (f0, f1, f2)
    }
}
