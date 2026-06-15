import AppKit

/// 메뉴바용 픽셀 코인 — 앱 아이콘과 동일한 도트 디자인의 16x16 그리드.
/// 회전은 클래식 코인 스핀 프레임(정면→옆면→뒷면) 방식이며,
/// 이징은 프레임별 지속시간으로 표현한다 (정면에서 길게 머물고 옆면은 빠르게 통과).
enum MenuBarCoin {
    enum FrameKind: CaseIterable, Hashable {
        case face, mid, narrow, edge, back
    }

    struct SpinFrame {
        let kind: FrameKind
        let duration: TimeInterval
    }

    struct Palette {
        let base: NSColor      // C
        let light: NSColor     // L
        let dark: NSColor      // D
        let outline: NSColor   // o
    }

    // 골드 (scripts/generate-icon.swift 와 동일)
    private static let goldPalette = Palette(
        base: NSColor(srgbRed: 0.965, green: 0.769, blue: 0.325, alpha: 1),
        light: NSColor(srgbRed: 0.992, green: 0.918, blue: 0.659, alpha: 1),
        dark: NSColor(srgbRed: 0.788, green: 0.569, blue: 0.180, alpha: 1),
        outline: NSColor(srgbRed: 0.357, green: 0.239, blue: 0.078, alpha: 1))

    // 경고용 레드 (리셋 전 한도 도달 예측 / 임계 초과 시)
    private static let warningPalette = Palette(
        base: NSColor(srgbRed: 0.910, green: 0.380, blue: 0.380, alpha: 1),
        light: NSColor(srgbRed: 1.000, green: 0.720, blue: 0.720, alpha: 1),
        dark: NSColor(srgbRed: 0.690, green: 0.220, blue: 0.220, alpha: 1),
        outline: NSColor(srgbRed: 0.380, green: 0.090, blue: 0.090, alpha: 1))

    // 정면 (T 각인)
    private static let face: [String] = [
        "................",
        "................",
        "......oooo......",
        "....ooLLLLoo....",
        "...oLLLLLLLLo...",
        "...oCCCCCCCCo...",
        "..oCCDDDDDDCCo..",
        "..oCCCCDDCCCCo..",
        "..oCCCCDDCCCCo..",
        "..oCCCCDDCCCCo..",
        "...oCCCDDCCCo...",
        "...oCCCCCCCCo...",
        "....ooDDDDoo....",
        "......oooo......",
        "................",
        "................",
    ]

    // 뒷면 (민무늬)
    private static let back: [String] = [
        "................",
        "................",
        "......oooo......",
        "....ooLLLLoo....",
        "...oLLLLLLLLo...",
        "...oCCCCCCCCo...",
        "..oCCCCCCCCCCo..",
        "..oCCCCCCCCCCo..",
        "..oCCCCCCCCCCo..",
        "..oCCCCCCCCCCo..",
        "...oCCCCCCCCo...",
        "...oCCCCCCCCo...",
        "....ooDDDDoo....",
        "......oooo......",
        "................",
        "................",
    ]

    // 비스듬 (8px 폭)
    private static let mid: [String] = [
        "................",
        "................",
        "......oooo......",
        ".....oLLLLo.....",
        "....oLLLLLLo....",
        "....oCCCCCCo....",
        "....oCCCCCCo....",
        "....oCCCCCCo....",
        "....oCCCCCCo....",
        "....oCCCCCCo....",
        "....oCCCCCCo....",
        "....oDDDDDDo....",
        ".....oDDDDo.....",
        "......oooo......",
        "................",
        "................",
    ]

    // 더 비스듬 (4px 폭)
    private static let narrow: [String] = [
        "................",
        "................",
        ".......oo.......",
        "......oLLo......",
        "......oLLo......",
        "......oCCo......",
        "......oCCo......",
        "......oCCo......",
        "......oCCo......",
        "......oCCo......",
        "......oCCo......",
        "......oDDo......",
        "......oDDo......",
        ".......oo.......",
        "................",
        "................",
    ]

    // 옆면 (2px 폭)
    private static let edge: [String] = [
        "................",
        "................",
        ".......oo.......",
        ".......LD.......",
        ".......LD.......",
        ".......LD.......",
        ".......LD.......",
        ".......LD.......",
        ".......LD.......",
        ".......LD.......",
        ".......LD.......",
        ".......LD.......",
        ".......LD.......",
        ".......oo.......",
        "................",
        "................",
    ]

    /// 티어별 스핀 시퀀스 — 빠른 티어일수록 회전은 빨라지되 프레임을 드랍해서
    /// 초당 이미지 교체를 ~5회로 상한 (교체 1회당 메뉴바 재렌더 비용 ≈ CPU 1%/s 실측)
    static func sequence(for tier: SpinTier) -> [SpinFrame] {
        switch tier {
        case .idle:     // 1바퀴 ≈ 4.9초, ~2.4 swaps/s
            return fullCycle(faceHold: 2.0)
        case .normal:   // 1바퀴 ≈ 2.7초, ~4.4 swaps/s
            return fullCycle(faceHold: 0.9)
        case .fast:     // 8프레임, 1바퀴 ≈ 1.5초, ~5.3 swaps/s
            return [
                SpinFrame(kind: .face, duration: 0.50),
                SpinFrame(kind: .mid, duration: 0.09),
                SpinFrame(kind: .edge, duration: 0.07),
                SpinFrame(kind: .mid, duration: 0.09),
                SpinFrame(kind: .back, duration: 0.50),
                SpinFrame(kind: .mid, duration: 0.09),
                SpinFrame(kind: .edge, duration: 0.07),
                SpinFrame(kind: .mid, duration: 0.09),
            ]
        case .blazing:  // 4프레임, 1바퀴 ≈ 0.76초, ~5.3 swaps/s
            return [
                SpinFrame(kind: .face, duration: 0.30),
                SpinFrame(kind: .narrow, duration: 0.08),
                SpinFrame(kind: .back, duration: 0.30),
                SpinFrame(kind: .narrow, duration: 0.08),
            ]
        }
    }

    private static func fullCycle(faceHold: TimeInterval) -> [SpinFrame] {
        [
            SpinFrame(kind: .face, duration: faceHold),
            SpinFrame(kind: .mid, duration: 0.12),
            SpinFrame(kind: .narrow, duration: 0.08),
            SpinFrame(kind: .edge, duration: 0.06),
            SpinFrame(kind: .narrow, duration: 0.08),
            SpinFrame(kind: .mid, duration: 0.12),
            SpinFrame(kind: .back, duration: faceHold),
            SpinFrame(kind: .mid, duration: 0.12),
            SpinFrame(kind: .narrow, duration: 0.08),
            SpinFrame(kind: .edge, duration: 0.06),
            SpinFrame(kind: .narrow, duration: 0.08),
            SpinFrame(kind: .mid, duration: 0.12),
        ]
    }

    private static func grid(for kind: FrameKind) -> [String] {
        switch kind {
        case .face: return face
        case .mid: return mid
        case .narrow: return narrow
        case .edge: return edge
        case .back: return back
        }
    }

    /// 프레임 이미지 캐시 (종류 × 팔레트)
    private static let goldImages: [FrameKind: NSImage] =
        Dictionary(uniqueKeysWithValues: FrameKind.allCases.map { ($0, render(grid(for: $0), palette: goldPalette)) })
    private static let warningImages: [FrameKind: NSImage] =
        Dictionary(uniqueKeysWithValues: FrameKind.allCases.map { ($0, render(grid(for: $0), palette: warningPalette)) })

    static func image(for kind: FrameKind, warning: Bool = false) -> NSImage {
        (warning ? warningImages : goldImages)[kind] ?? NSImage()
    }

    static func staticImage(warning: Bool = false) -> NSImage {
        image(for: .face, warning: warning)
    }

    private static func color(for ch: Character, palette: Palette) -> NSColor? {
        switch ch {
        case "o": return palette.outline
        case "C": return palette.base
        case "L": return palette.light
        case "D": return palette.dark
        default: return nil
        }
    }

    /// 비트맵으로 미리 래스터라이즈 — drawingHandler 방식은 메뉴바가 다시 그릴 때마다
    /// 그리드를 재그려서 스핀 중 CPU 를 소모하므로 캐시된 비트맵으로 교체만 한다.
    private static func render(_ grid: [String], palette: Palette) -> NSImage {
        let scale = 2  // @2x 레티나
        let px = 16 * scale
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return NSImage(size: NSSize(width: 16, height: 16)) }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        for (row, line) in grid.enumerated() {
            for (col, ch) in line.enumerated() {
                guard col < 16, let c = color(for: ch, palette: palette) else { continue }
                c.setFill()
                NSRect(x: CGFloat(col * scale), y: CGFloat((15 - row) * scale),
                       width: CGFloat(scale), height: CGFloat(scale)).fill()
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.addRepresentation(rep)
        return image
    }
}
