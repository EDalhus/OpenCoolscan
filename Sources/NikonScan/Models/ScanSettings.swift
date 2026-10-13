import Foundation
import CoreGraphics

enum FilmType: String, CaseIterable, Identifiable {
    case colorNegative  = "Color Negative (Default)"
    case colorPositive  = "Color Positive (Slide)"
    case bwNegative     = "B&W Negative"
    case bwPositive     = "B&W Positive"

    var id: String { rawValue }

    var isColor: Bool {
        switch self {
        case .colorNegative, .colorPositive: return true
        case .bwNegative, .bwPositive: return false
        }
    }

    var isNegative: Bool {
        switch self {
        case .colorNegative, .bwNegative: return true
        case .colorPositive, .bwPositive: return false
        }
    }

    var shortName: String {
        switch self {
        case .colorNegative: return "Neg (Color)"
        case .colorPositive: return "Pos/Slide"
        case .bwNegative:    return "Neg (B&W)"
        case .bwPositive:    return "Pos (B&W)"
        }
    }
}

enum BitDepth: String, CaseIterable, Identifiable {
    case bit8  = "8 bit/channel"
    case bit14 = "14/16 bit (when supported)"

    var id: String { rawValue }

    var bitsPerSample: Int {
        switch self {
        case .bit8:  return 8
        case .bit14: return 16
        }
    }
}

enum ColorSpace: String, CaseIterable, Identifiable {
    case sRGB      = "sRGB"
    case adobeRGB  = "Adobe RGB (1998)"
    case appleRGB  = "Apple RGB"
    case cieRGB    = "CIE RGB"
    case gray      = "Grayscale"

    var id: String { rawValue }
}

enum DigitalICE: String, CaseIterable, Identifiable {
    case off    = "OFF"
    case normal = "Normal"
    case fine   = "Fine"

    var id: String { rawValue }
}

enum OutputFormat: String, CaseIterable, Identifiable {
    case tiff = "TIFF"
    case jpeg = "JPEG"
    case png  = "PNG"

    var id: String { rawValue }

    var fileExtension: String {
        rawValue.lowercased()
    }

    var utTypeIdentifier: String {
        switch self {
        case .tiff: return "public.tiff"
        case .jpeg: return "public.jpeg"
        case .png:  return "public.png"
        }
    }
}

enum FilmPreset: String, CaseIterable, Identifiable {
    case none       = "None"
    case portra400  = "Portra 400"
    case portra160  = "Portra 160"
    case ektar100   = "Ektar 100"
    case velvia50   = "Velvia 50"
    case provia100  = "Provia 100F"
    case triX400    = "Tri-X 400"
    case hp5        = "HP5 Plus"

    var id: String { rawValue }

    func apply(to settings: ScanSettings) {
        settings.activePreset = self
        switch self {
        case .none:
            settings.brightness = 0
            settings.contrast = 0
            settings.gamma = 1
            settings.saturation = 0
            settings.colorBalance = .zero
            settings.curves = Curves()
        case .portra400:
            settings.filmType = .colorNegative
            settings.brightness = 0.15
            settings.contrast = -0.2
            settings.gamma = 1.05
            settings.saturation = -8
            settings.colorBalance = SIMD3(4, 2, -6)
        case .portra160:
            settings.filmType = .colorNegative
            settings.brightness = 0.1
            settings.contrast = -0.1
            settings.gamma = 1.02
            settings.saturation = -5
            settings.colorBalance = SIMD3(3, 1, -4)
        case .ektar100:
            settings.filmType = .colorNegative
            settings.brightness = 0.05
            settings.contrast = 0.35
            settings.gamma = 0.98
            settings.saturation = 18
            settings.colorBalance = SIMD3(2, -2, -4)
        case .velvia50:
            settings.filmType = .colorPositive
            settings.brightness = 0.1
            settings.contrast = 0.8
            settings.gamma = 0.92
            settings.saturation = 35
            settings.colorBalance = SIMD3(-4, 6, 2)
        case .provia100:
            settings.filmType = .colorPositive
            settings.brightness = 0.05
            settings.contrast = 0.25
            settings.gamma = 0.98
            settings.saturation = 10
            settings.colorBalance = SIMD3(-2, 2, 0)
        case .triX400:
            settings.filmType = .bwNegative
            settings.brightness = 0.1
            settings.contrast = 0.5
            settings.gamma = 1.1
            settings.saturation = -100
            settings.colorBalance = .zero
        case .hp5:
            settings.filmType = .bwNegative
            settings.brightness = 0.05
            settings.contrast = 0.3
            settings.gamma = 1.05
            settings.saturation = -100
            settings.colorBalance = .zero
        }
    }
}

struct CurvePoint: Equatable {
    var input: Double   // 0...1
    var output: Double  // 0...1
}

struct ToneCurve: Equatable {
    var points: [CurvePoint]

    static var linear: ToneCurve {
        ToneCurve(points: [
            CurvePoint(input: 0, output: 0),
            CurvePoint(input: 1, output: 1)
        ])
    }

    func output(for input: Double) -> Double {
        guard points.count >= 2 else { return input }
        let sorted = points.sorted { $0.input < $1.input }
        guard let first = sorted.first, let last = sorted.last else { return input }
        if input <= first.input { return first.output }
        if input >= last.input  { return last.output }
        for i in 0..<sorted.count - 1 {
            let p0 = sorted[i], p1 = sorted[i + 1]
            if input >= p0.input && input <= p1.input {
                let t = (input - p0.input) / (p1.input - p0.input)
                return p0.output + t * (p1.output - p0.output)
            }
        }
        return input
    }
}

struct Curves: Equatable {
    var composite: ToneCurve = .linear
    var red:       ToneCurve = .linear
    var green:     ToneCurve = .linear
    var blue:      ToneCurve = .linear
}

class ScanSettings: ObservableObject {
    @Published var filmType: FilmType = .colorNegative
    @Published var resolution: Int = 2400
    @Published var bitDepth: BitDepth = .bit8
    @Published var colorSpace: ColorSpace = .sRGB
    @Published var digitalICE: DigitalICE = .normal
    @Published var outputFormat: OutputFormat = .tiff

    // Tone adjustments
    @Published var brightness: Double = 0.0   // -3...3 EV
    @Published var contrast: Double = 0.0     // -3...3
    @Published var gamma: Double = 1.0        // 0.2...3.0
    @Published var curves: Curves = Curves()

    // Color adjustments
    @Published var colorBalance: SIMD3<Double> = .zero  // R, G, B offset
    @Published var saturation: Double = 0.0             // -100...100
    @Published var colorBrightness: Double = 0.0        // -100...100 (Color Balance ▸ Brightness)

    // Analog gain per channel, in EV (-2...2); master gain is `brightness`
    @Published var analogGain: SIMD3<Double> = .zero

    // Unsharp mask
    @Published var usmIntensity: Double = 50    // 0...100 %
    @Published var usmHaloWidth: Double = 5     // 0...100 px
    @Published var usmThreshold: Double = 4     // 0...100 levels

    // Digital ICE⁴ post processing
    @Published var icePostProcessing: Bool = false
    @Published var rocLevel: Double = 5         // 0...10
    @Published var gemLevel: Double = 3         // 0...4
    @Published var deeEnabled: Bool = false
    @Published var deeShadow: Double = 50       // 0...100

    // Scan Image Enhancer (automatic tone/color correction)
    @Published var sieEnabled: Bool = false

    // Scan area (normalized 0...1)
    @Published var cropRect: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    // Hardware
    @Published var autoFocus: Bool = true
    @Published var focusPosition: Double = 0.0  // manual focus: -5...5 mm
    @Published var manualFocusSteps: Int = 236  // Scanner Extras ▸ Manual Focus Adjustment (0...500)
    @Published var exposureLock: Bool = false
    @Published var multiScan: Bool = false
    @Published var multiScanCount: Int = 4     // 4 or 8x averaging

    // Display
    @Published var rotation: Int = 0  // 0, 90, 180, 270 degrees
    @Published var showOriginal: Bool = false
    @Published var activePreset: FilmPreset = .none

    // Frame alignment
    @Published var autoAlign: Bool = true
    @Published var alignmentOffset: Int = 0  // extra pixels to trim from right (+) or restore (-)

    var isGrayscale: Bool {
        !filmType.isColor || colorSpace == .gray
    }

    func applyDefaultsFromPreferences() {
        let dpi = UserDefaults.standard.object(forKey: "defaultDPI") as? Int ?? 2400
        resolution = dpi
        if let raw = UserDefaults.standard.string(forKey: "workingColorSpace"),
           let space = ColorSpace(rawValue: raw) {
            colorSpace = space
        }
    }

    func reset() {
        brightness = 0
        contrast = 0
        gamma = 1
        curves = Curves()
        colorBalance = .zero
        saturation = 0
        colorBrightness = 0
        analogGain = .zero
        usmIntensity = 50
        usmHaloWidth = 5
        usmThreshold = 4
        icePostProcessing = false
        rocLevel = 5
        gemLevel = 3
        deeEnabled = false
        deeShadow = 50
        sieEnabled = false
        cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        rotation = 0
        autoAlign = true
        alignmentOffset = 0
        activePreset = .none
        showOriginal = false
    }
}
