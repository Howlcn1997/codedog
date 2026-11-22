// 生成 dmg 安装窗口的背景图（660×400，1x + 2x 合成一个 tiff）。
// 底图 background-art.jpg 由文生图模型（GPT-Image）生成：浅色珠光底 + 居中细线渐变箭头 + 两个图标位下的柔和投影；
// 这里把它裁成窗口比例，盖掉底部的杂痕，再叠上安装提示文字。
// 用法：swift scripts/dmg/make-background.swift   产物：scripts/dmg/background.tiff
// 图标位置要和 scripts/dmg/settings.py 里的 icon_locations 对上：codedog (170, 180)，Applications (490, 180)。
import AppKit

let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let size = CGSize(width: 660, height: 400)

guard let art = NSImage(contentsOf: dir.appending(path: "background-art.jpg")),
      let artCG = art.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("读不到 background-art.jpg") }

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    cg.interpolationQuality = .high

    // 底图按宽度铺满，上下等量裁掉（原图 3:2，窗口 1.65:1）
    let w = CGFloat(artCG.width), h = CGFloat(artCG.height)
    let drawH = size.width * h / w
    cg.draw(artCG, in: CGRect(x: 0, y: (size.height - drawH) / 2, width: size.width, height: drawH))

    // 底部用底色渐隐盖住生成图里的杂痕，给文字一块干净的地方（CG 原点在左下）
    let bg = CGColor(red: 0.973, green: 0.973, blue: 0.99, alpha: 1)
    let fade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [bg, bg.copy(alpha: 0)!] as CFArray, locations: [0.35, 1])!
    cg.drawLinearGradient(fade, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 150), options: [])

    func text(_ s: String, size fontSize: CGFloat, weight: NSFont.Weight, alpha: CGFloat, centerYFromTop: CGFloat, kern: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let str = NSAttributedString(string: s, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: NSColor(red: 0.13, green: 0.12, blue: 0.22, alpha: alpha),
            .paragraphStyle: style,
            .kern: kern,
        ])
        let lineH = str.size().height
        str.draw(in: CGRect(x: 0, y: size.height - centerYFromTop - lineH / 2, width: size.width, height: lineH))
    }
    text("拖到 Applications 文件夹即可完成安装", size: 13, weight: .medium, alpha: 0.72, centerYFromTop: 330, kern: 0.6)
    text("DRAG CODEDOG TO APPLICATIONS", size: 9.5, weight: .semibold, alpha: 0.32, centerYFromTop: 352, kern: 1.6)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = dir.appending(path: "background.tiff")
let image = NSImage(size: size)
image.addRepresentation(render(scale: 1))
image.addRepresentation(render(scale: 2))
guard let tiff = image.tiffRepresentation(using: .lzw, factor: 1) else { fatalError("tiff 编码失败") }
try tiff.write(to: out)
print("wrote \(out.path)")
