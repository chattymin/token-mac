// 도트(픽셀 아트) 앱 아이콘 생성기
// 사용: swift scripts/generate-icon.swift <출력.png>
// 16x16 픽셀 그리드 — 다크 배경 + 상승 바 차트 3개 + 골드 토큰 코인
import AppKit

let args = CommandLine.arguments
let outPath = args.count > 1 ? args[1] : "build/icon_1024.png"

// 팔레트
let BG = NSColor(srgbRed: 0.133, green: 0.169, blue: 0.271, alpha: 1)      // #222B45
let BG2 = NSColor(srgbRed: 0.157, green: 0.196, blue: 0.314, alpha: 1)     // #283250 (디더링 톤)
let BASE = NSColor(srgbRed: 0.227, green: 0.271, blue: 0.400, alpha: 1)    // #3A4566 베이스라인
let G1 = NSColor(srgbRed: 0.180, green: 0.769, blue: 0.651, alpha: 1)      // #2EC4A6 green bar
let G2 = NSColor(srgbRed: 0.361, green: 0.910, blue: 0.784, alpha: 1)      // top shine
let A1 = NSColor(srgbRed: 1.000, green: 0.714, blue: 0.153, alpha: 1)      // #FFB627 amber bar
let A2 = NSColor(srgbRed: 1.000, green: 0.851, blue: 0.490, alpha: 1)
let P1 = NSColor(srgbRed: 0.937, green: 0.365, blue: 0.498, alpha: 1)      // #EF5D7F pink bar
let P2 = NSColor(srgbRed: 1.000, green: 0.561, blue: 0.659, alpha: 1)
let C1 = NSColor(srgbRed: 0.965, green: 0.769, blue: 0.325, alpha: 1)      // #F6C453 coin
let C2 = NSColor(srgbRed: 0.992, green: 0.918, blue: 0.659, alpha: 1)      // coin highlight
let C3 = NSColor(srgbRed: 0.788, green: 0.569, blue: 0.180, alpha: 1)      // coin shadow

// 16x16 그리드 (row 0 = 위). 문자 → 색상
// . = 배경, : = 배경 디더링, _ = 베이스라인
// g/G = green bar(밝음/기본), a/A = amber, p/P = pink
// c = coin, h = coin highlight, s = coin shadow
// 레트로 게임풍 골드 코인 (12x12 픽셀 서클, cols 2-13 / rows 2-13)
// o=외곽선, L=림 하이라이트, C=골드 베이스, D=음영, 슬롯=L+DD 세로 바
let grid: [String] = [
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

let OUT = NSColor(srgbRed: 0.357, green: 0.239, blue: 0.078, alpha: 1)     // #5B3D14 코인 외곽선

func color(for ch: Character, col: Int, row: Int) -> NSColor? {
    switch ch {
    case ".": return (col + row) % 5 == 0 ? BG2 : nil   // 미세 디더링
    case "o": return OUT
    case "C": return C1
    case "L": return C2
    case "D": return C3
    default: return nil
    }
}

let size = 1024
let margin = 64               // macOS 아이콘 여백 관례
let rectSize = size - margin * 2   // 896
let corner = 200.0
let cell = CGFloat(rectSize) / 16.0  // 56

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let iconRect = NSRect(x: margin, y: margin, width: rectSize, height: rectSize)
let path = NSBezierPath(roundedRect: iconRect, xRadius: corner, yRadius: corner)
BG.setFill()
path.fill()
path.addClip()

for (row, line) in grid.enumerated() {
    for (col, ch) in line.enumerated() {
        guard col < 16, let c = color(for: ch, col: col, row: row) else { continue }
        c.setFill()
        // NSImage 좌표계는 아래가 원점 → row 반전
        let x = CGFloat(margin) + CGFloat(col) * cell
        let y = CGFloat(margin) + CGFloat(15 - row) * cell
        NSRect(x: x, y: y, width: cell, height: cell).fill()
    }
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("PNG 인코딩 실패\n".data(using: .utf8)!)
    exit(1)
}
try? FileManager.default.createDirectory(
    atPath: (outPath as NSString).deletingLastPathComponent,
    withIntermediateDirectories: true)
do {
    try png.write(to: URL(fileURLWithPath: outPath))
    print("saved: \(outPath)")
} catch {
    FileHandle.standardError.write("쓰기 실패: \(error)\n".data(using: .utf8)!)
    exit(1)
}
