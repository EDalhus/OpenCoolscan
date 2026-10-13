import Foundation

enum ScannerModel: String, CaseIterable, Identifiable {
    case ls4000 = "LS-4000 ED"
    case ls5000 = "LS-5000 ED"
    case ls8000 = "LS-8000 ED"
    case ls9000 = "LS-9000 ED"
    case ls40   = "LS-40 (Coolscan IV)"
    case ls50   = "LS-50 (Coolscan V)"
    case ls2000 = "LS-2000"
    case ls30   = "LS-30 (Coolscan III)"
    case simulated = "Simulated Scanner"

    var id: String { rawValue }

    // USB Product IDs (Vendor: 0x04B0 = Nikon)
    // Note: LS-4000 and LS-50 both report 0x4001 — disambiguate via USB product string.
    var usbProductID: UInt16 {
        switch self {
        case .ls4000:    return 0x4001
        case .ls5000:    return 0x4002
        case .ls8000:    return 0x4004
        case .ls9000:    return 0x4003
        case .ls40:      return 0x4000
        case .ls50:      return 0x4001
        case .ls2000:    return 0x4020
        case .ls30:      return 0x4030
        case .simulated: return 0x0000
        }
    }

    var maxOpticalResolution: Int {
        switch self {
        case .ls4000:    return 4000
        case .ls5000:    return 4000
        case .ls8000:    return 4000
        case .ls9000:    return 4000
        case .ls40:      return 2900
        case .ls50:      return 4000
        case .ls2000:    return 2000
        case .ls30:      return 2700
        case .simulated: return 4000
        }
    }

    var supportsDigitalICE: Bool {
        switch self {
        case .ls2000, .ls30, .simulated: return false
        default: return true
        }
    }

    var supportsMultipleFilmFormats: Bool {
        switch self {
        case .ls8000, .ls9000: return true
        default: return false
        }
    }

    var availableResolutions: [Int] {
        let max = maxOpticalResolution
        var res = [300, 600, 1200, 2400]
        if max >= 2700 { res.append(2700) }
        if max >= 2900 { res.append(2900) }
        if max >= 4000 { res.append(4000) }
        return res
    }

    /// Resolve model from USB product ID + optional product name string.
    static func resolve(productID: UInt16, productName: String?) -> ScannerModel? {
        let name = (productName ?? "").lowercased()

        // Ambiguous PID shared by LS-4000 ED and LS-50 (Coolscan V)
        if productID == 0x4001 {
            if name.contains("ls-50") || name.contains("coolscan v") || name.contains("coolscanv") {
                return .ls50
            }
            if name.contains("ls-4000") || name.contains("4000") {
                return .ls4000
            }
            // Prefer LS-50 for modern hardware when name is missing/unclear
            // (LS-4000 is much rarer in active use). Fall back to product-name heuristics.
            return name.isEmpty ? .ls4000 : .ls50
        }

        return allCases.first(where: { $0.usbProductID == productID && $0 != .simulated })
    }
}

struct ScannerDevice: Identifiable, Equatable, Hashable {
    let id: UUID
    let model: ScannerModel
    var isConnected: Bool
    var locationID: UInt32

    var name: String { model.rawValue }

    static func == (lhs: ScannerDevice, rhs: ScannerDevice) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static let simulated = ScannerDevice(
        id: UUID(),
        model: .simulated,
        isConnected: true,
        locationID: 0
    )
}
