//
//  PresetManager.swift
//  iRetro
//
//  Deployment Target: iOS 12.0+ (Supports iPhone 5S / Apple A7 / 1GB RAM)
//  Frameworks: UIKit, CoreImage
//

import UIKit
import CoreImage

/// Model untuk satu preset simulasi film (3D LUT).
public struct FilmPreset {
    public let id: String
    public let name: String
    public let shortCode: String
    public let accentColor: UIColor
    public let dimension: Int
    public let rgbaCubeData: Data
    public let isCustom: Bool
    public let sourceFileURL: URL?

    /// Membuat instance `CIFilter` (`CIColorCubeWithColorSpace`) siap pakai dari data LUT.
    public func makeFilter() -> CIFilter? {
        return try? CubeLUTParser.makeColorCubeFilter(
            fromPremultipliedRGBAData: rgbaCubeData,
            dimension: dimension
        )
    }
}

/// Pengelola preset simulasi film bawaan (`.cube`) dan preset kustom yang diimpor pengguna ke Document Directory.
public final class PresetManager {

    public static let shared = PresetManager()

    /// Daftar seluruh preset yang tersedia (5 preset bawaan + preset `.cube` kustom).
    public private(set) var presets: [FilmPreset] = []

    /// Nama direktori penyimpanan file `.cube` kustom di dalam `Documents/`.
    private let customLUTDirectoryName = "CustomLUTs"

    /// Ukuran dimensi 3D LUT default untuk generator fallback `.cube` bawaan (`17x17x17` = ringan & akurat di A7).
    private let builtInLUTDimension = 17

    private init() {
        reloadAllPresets()
    }

    // MARK: - Public API

    /// Memuat ulang 5 preset film bawaan serta seluruh file `.cube` kustom dari Document Directory.
    public func reloadAllPresets() {
        var loaded: [FilmPreset] = []
        loaded.append(contentsOf: loadBuiltInPresets())
        loaded.append(contentsOf: loadCustomPresetsFromDisk())
        self.presets = loaded
    }

    /// Mengimpor file `.cube` dari `UIDocumentPickerViewController`, memvalidasinya via `CubeLUTParser`,
    /// menyimpannya secara lokal ke `Documents/CustomLUTs/`, dan menambahkannya ke daftar preset.
    @discardableResult
    public func importCustomCubeFile(from externalURL: URL) throws -> FilmPreset {
        let shouldStopAccessing = externalURL.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                externalURL.stopAccessingSecurityScopedResource()
            }
        }

        // 1. Validasi dan parse file .cube terlebih dahulu di dalam autoreleasepool
        var parsedLUT: ParsedCubeLUT!
        var parseError: Error?
        autoreleasepool {
            do {
                parsedLUT = try CubeLUTParser.parse(fileURL: externalURL)
            } catch {
                parseError = error
            }
        }
        if let error = parseError {
            throw error
        }

        // 2. Pastikan direktori Documents/CustomLUTs tersedia
        let customDir = try ensureCustomLUTDirectory()
        let rawName = externalURL.deletingPathExtension().lastPathComponent
        let sanitizedBase = sanitizeFileName(rawName)
        let destinationFileName = "\(sanitizedBase).cube"
        let destinationURL = customDir.appendingPathComponent(destinationFileName)

        // Jika sudah ada file dengan nama yang sama, timpa dengan versi terbaru
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: externalURL, to: destinationURL)

        let displayName = (parsedLUT.title?.isEmpty == false) ? parsedLUT.title! : rawName
        let shortCode = String(sanitizedBase.uppercased().prefix(4))

        let newPreset = FilmPreset(
            id: "custom_\(sanitizedBase.lowercased())",
            name: displayName,
            shortCode: shortCode.isEmpty ? "CUST" : shortCode,
            accentColor: UIColor(red: 0.90, green: 0.48, blue: 0.22, alpha: 1.0),
            dimension: parsedLUT.dimension,
            rgbaCubeData: parsedLUT.rgbaCubeData,
            isCustom: true,
            sourceFileURL: destinationURL
        )

        // Perbarui atau tambahkan ke array presets
        if let existingIndex = presets.firstIndex(where: { $0.id == newPreset.id }) {
            presets[existingIndex] = newPreset
        } else {
            presets.append(newPreset)
        }

        return newPreset
    }

    // MARK: - Built-in Presets Loader

    private enum BuiltInSimulation: CaseIterable {
        case japaneseAiry
        case fujiClassicChrome
        case fujiProNeg
        case kodakPortra400
        case kodakGold200

        var id: String {
            switch self {
            case .japaneseAiry:      return "builtin_japanese_airy"
            case .fujiClassicChrome: return "builtin_fuji_classic_chrome"
            case .fujiProNeg:        return "builtin_fuji_pro_neg"
            case .kodakPortra400:    return "builtin_kodak_portra_400"
            case .kodakGold200:      return "builtin_kodak_gold_200"
            }
        }

        var displayName: String {
            switch self {
            case .japaneseAiry:      return "Japanese Airy"
            case .fujiClassicChrome: return "Fuji Classic Chrome"
            case .fujiProNeg:        return "Fuji Pro Neg"
            case .kodakPortra400:    return "Kodak Portra 400"
            case .kodakGold200:      return "Kodak Gold 200"
            }
        }

        var shortCode: String {
            switch self {
            case .japaneseAiry:      return "AIRY"
            case .fujiClassicChrome: return "CHRM"
            case .fujiProNeg:        return "PNEG"
            case .kodakPortra400:    return "P400"
            case .kodakGold200:      return "G200"
            }
        }

        var bundleFileName: String {
            switch self {
            case .japaneseAiry:      return "JapaneseAiry"
            case .fujiClassicChrome: return "FujiClassicChrome"
            case .fujiProNeg:        return "FujiProNeg"
            case .kodakPortra400:    return "KodakPortra400"
            case .kodakGold200:      return "KodakGold200"
            }
        }

        var accentColor: UIColor {
            switch self {
            case .japaneseAiry:      return UIColor(red: 0.56, green: 0.84, blue: 0.88, alpha: 1.0)
            case .fujiClassicChrome: return UIColor(red: 0.45, green: 0.65, blue: 0.58, alpha: 1.0)
            case .fujiProNeg:        return UIColor(red: 0.78, green: 0.67, blue: 0.60, alpha: 1.0)
            case .kodakPortra400:    return UIColor(red: 0.91, green: 0.64, blue: 0.34, alpha: 1.0)
            case .kodakGold200:      return UIColor(red: 0.95, green: 0.78, blue: 0.24, alpha: 1.0)
            }
        }

        /// Transformasi warna 3D LUT untuk menghasilkan file `.cube` bawaan jika file fisik belum disertakan di Bundle.
        func transform(r: Float, g: Float, b: Float) -> (Float, Float, Float) {
            let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b

            switch self {
            case .japaneseAiry:
                // High-key, lifted shadows, pastel cyan/mint tint, soft contrast
                let liftR = powf(r, 0.84) * 0.94 + 0.05
                let liftG = powf(g, 0.82) * 0.96 + 0.06
                let liftB = powf(b, 0.80) * 0.97 + 0.07
                let desat: Float = 0.86
                let outR = luma + (liftR - luma) * desat
                let outG = luma + (liftG - luma) * desat + 0.015
                let outB = luma + (liftB - luma) * desat + 0.025
                return (clamp(outR), clamp(outG), clamp(outB))

            case .fujiClassicChrome:
                // Documentary look: deeper shadows, muted saturation, warm highlights & cool cyan shadows
                let curveR = sCurve(r, strength: 1.22)
                let curveG = sCurve(g, strength: 1.18)
                let curveB = sCurve(b, strength: 1.15)
                let desat: Float = 0.76
                var outR = luma + (curveR - luma) * desat
                var outG = luma + (curveG - luma) * desat
                var outB = luma + (curveB - luma) * desat
                // Cyan-teal shadow / warm highlight split
                outR += (luma - 0.4) * 0.04
                outG += 0.01
                outB += (0.5 - luma) * 0.05
                return (clamp(outR), clamp(outG), clamp(outB))

            case .fujiProNeg:
                // Soft portrait rendering: lifted blacks, gentle highlight roll-off, natural warm skin tones
                let softR = 0.04 + 0.93 * powf(r, 0.94)
                let softG = 0.035 + 0.93 * powf(g, 0.96)
                let softB = 0.035 + 0.92 * powf(b, 0.98)
                let desat: Float = 0.90
                let outR = luma + (softR - luma) * desat + 0.012
                let outG = luma + (softG - luma) * desat + 0.004
                let outB = luma + (softB - luma) * desat - 0.006
                return (clamp(outR), clamp(outG), clamp(outB))

            case .kodakPortra400:
                // Golden-warm skin luminance, rich midtones, subtle amber highlight & clean shadow
                let curveR = sCurve(powf(r, 0.93), strength: 1.12)
                let curveG = sCurve(powf(g, 0.95), strength: 1.10)
                let curveB = sCurve(powf(b, 0.98), strength: 1.08)
                let sat: Float = 1.06
                let outR = luma + (curveR - luma) * sat + 0.022
                let outG = luma + (curveG - luma) * sat + 0.008
                let outB = luma + (curveB - luma) * sat - 0.018
                return (clamp(outR), clamp(outG), clamp(outB))

            case .kodakGold200:
                // Vintage consumer film: punchy contrast, warm golden yellows, nostalgic magenta-amber bias
                let curveR = sCurve(powf(r, 0.90), strength: 1.20)
                let curveG = sCurve(powf(g, 0.93), strength: 1.16)
                let curveB = sCurve(powf(b, 1.03), strength: 1.14)
                let sat: Float = 1.12
                let outR = luma + (curveR - luma) * sat + 0.032
                let outG = luma + (curveG - luma) * sat + 0.016
                let outB = luma + (curveB - luma) * sat - 0.035
                return (clamp(outR), clamp(outG), clamp(outB))
            }
        }

        private func sCurve(_ x: Float, strength: Float) -> Float {
            let clamped = min(max(x, 0.0), 1.0)
            let centered = clamped - 0.5
            let curved = 0.5 + centered * strength / (1.0 + abs(centered) * (strength - 1.0) * 2.0)
            return min(max(curved, 0.0), 1.0)
        }

        private func clamp(_ v: Float) -> Float {
            return min(max(v, 0.0), 1.0)
        }
    }

    private func loadBuiltInPresets() -> [FilmPreset] {
        var results: [FilmPreset] = []

        for simulation in BuiltInSimulation.allCases {
            autoreleasepool {
                // 1. Cek apakah ada file .cube di Bundle aplikasi
                if let bundleURL = Bundle.main.url(forResource: simulation.bundleFileName, withExtension: "cube"),
                   let parsed = try? CubeLUTParser.parse(fileURL: bundleURL) {
                    results.append(
                        FilmPreset(
                            id: simulation.id,
                            name: simulation.displayName,
                            shortCode: simulation.shortCode,
                            accentColor: simulation.accentColor,
                            dimension: parsed.dimension,
                            rgbaCubeData: parsed.rgbaCubeData,
                            isCustom: false,
                            sourceFileURL: bundleURL
                        )
                    )
                    return
                }

                // 2. Fallback: generate string .cube standar dan lewatkan ke CubeLUTParser
                //    agar tetap memvalidasi pipeline .cube parser 100% end-to-end.
                let cubeText = generateCubeFileString(for: simulation, dimension: builtInLUTDimension)
                if let parsed = try? CubeLUTParser.parse(cubeString: cubeText, fallbackTitle: simulation.displayName) {
                    results.append(
                        FilmPreset(
                            id: simulation.id,
                            name: simulation.displayName,
                            shortCode: simulation.shortCode,
                            accentColor: simulation.accentColor,
                            dimension: parsed.dimension,
                            rgbaCubeData: parsed.rgbaCubeData,
                            isCustom: false,
                            sourceFileURL: nil
                        )
                    )
                }
            }
        }

        return results
    }

    /// Menghasilkan isi teks `.cube` standar (`TITLE`, `LUT_3D_SIZE`, `DOMAIN_MIN`, `DOMAIN_MAX`, dan `N^3` baris RGB).
    private func generateCubeFileString(for simulation: BuiltInSimulation, dimension: Int) -> String {
        var lines: [String] = []
        lines.reserveCapacity(dimension * dimension * dimension + 6)
        lines.append("# Generated by i-Retro Built-in Film Simulation Engine")
        lines.append("TITLE \"\(simulation.displayName)\"")
        lines.append("LUT_3D_SIZE \(dimension)")
        lines.append("DOMAIN_MIN 0.0 0.0 0.0")
        lines.append("DOMAIN_MAX 1.0 1.0 1.0")

        let denom = Float(dimension - 1)
        // Dalam spesifikasi .cube: Red berubah paling cepat, kemudian Green, kemudian Blue.
        for bIndex in 0..<dimension {
            let b = Float(bIndex) / denom
            for gIndex in 0..<dimension {
                let g = Float(gIndex) / denom
                for rIndex in 0..<dimension {
                    let r = Float(rIndex) / denom
                    let (outR, outG, outB) = simulation.transform(r: r, g: g, b: b)
                    lines.append(String(format: "%.6f %.6f %.6f", outR, outG, outB))
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Custom Presets Persistence

    private func loadCustomPresetsFromDisk() -> [FilmPreset] {
        guard let customDir = try? ensureCustomLUTDirectory() else { return [] }
        guard let fileURLs = try? FileManager.default.contentsOfDirectory(
            at: customDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let cubeURLs = fileURLs
            .filter { $0.pathExtension.lowercased() == "cube" }
            .sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }

        var customPresets: [FilmPreset] = []
        for url in cubeURLs {
            autoreleasepool {
                if let parsed = try? CubeLUTParser.parse(fileURL: url) {
                    let baseName = url.deletingPathExtension().lastPathComponent
                    let displayName = (parsed.title?.isEmpty == false) ? parsed.title! : baseName
                    let shortCode = String(sanitizeFileName(baseName).uppercased().prefix(4))
                    customPresets.append(
                        FilmPreset(
                            id: "custom_\(baseName.lowercased())",
                            name: displayName,
                            shortCode: shortCode.isEmpty ? "CUST" : shortCode,
                            accentColor: UIColor(red: 0.90, green: 0.48, blue: 0.22, alpha: 1.0),
                            dimension: parsed.dimension,
                            rgbaCubeData: parsed.rgbaCubeData,
                            isCustom: true,
                            sourceFileURL: url
                        )
                    )
                }
            }
        }
        return customPresets
    }

    private func ensureCustomLUTDirectory() throws -> URL {
        guard let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw CubeLUTError.unreadableFile("Document directory tidak tersedia.")
        }
        let customDir = docsURL.appendingPathComponent(customLUTDirectoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: customDir.path) {
            try FileManager.default.createDirectory(at: customDir, withIntermediateDirectories: true, attributes: nil)
        }
        return customDir
    }

    private func sanitizeFileName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let scalars = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : Character("_") }
        let cleaned = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return cleaned.isEmpty ? "CustomLUT" : cleaned
    }
}
