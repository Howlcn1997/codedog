// 生成 dmg 安装窗口的背景图（660×400，1x + 2x 合成一个 tiff）。
// 用法：swift scripts/dmg/make-background.swift   产物：scripts/dmg/background.tiff
// 图标位置要和 scripts/dmg/settings.py 里的 icon_locations 对上：codedog (170, 180)，Applications (490, 180)。
import AppKit

let size = CGSize(width: 660, height: 400)
let appX: CGFloat = 170, appsX: CGFloat = 490, iconY: CGFloat = 180   // Finder 坐标（原点左上）

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    // 翻转成左上原点，和 Finder 的图标坐标一致
    cg.translateBy(x: 0, y: size.height)
    cg.scaleBy(x: 1, y: -1)

    // 底色：浅色（Finder 在自定义背景上固定用深色文字显示图标名，背景必须浅），上白下微灰紫
    let base = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [CGColor(red: 0.985, green: 0.983, blue: 0.995, alpha: 1),
                                   CGColor(red: 0.925, green: 0.918, blue: 0.95, alpha: 1)] as CFArray,
                          locations: [0, 1])!
    cg.drawLinearGradient(base, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])

    // 品牌紫的柔光，压在两个图标中间偏上
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [CGColor(red: 0.40, green: 0.39, blue: 0.86, alpha: 0.13),
                                   CGColor(red: 0.40, green: 0.39, blue: 0.86, alpha: 0)] as CFArray,
                          locations: [0, 1])!
    cg.drawRadialGradient(glow, startCenter: CGPoint(x: size.width / 2, y: iconY - 10), startRadius: 0,
                          endCenter: CGPoint(x: size.width / 2, y: iconY - 10), endRadius: 300, options: [])

    // 两个图标下方的托盘：很淡的圆角底，让图标"落"在上面
    for x in [appX, appsX] {
        let plate = CGRect(x: x - 92, y: iconY - 88, width: 184, height: 196)
        cg.addPath(CGPath(roundedRect: plate, cornerWidth: 28, cornerHeight: 28, transform: nil))
        cg.setFillColor(CGColor(red: 0.2, green: 0.18, blue: 0.4, alpha: 0.045))
        cg.fillPath()
        cg.addPath(CGPath(roundedRect: plate.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 28, cornerHeight: 28, transform: nil))
        cg.setStrokeColor(CGColor(red: 0.2, green: 0.18, blue: 0.4, alpha: 0.08))
        cg.setLineWidth(1)
        cg.strokePath()
    }

    // 箭头：圆点虚线 + 箭头
    let y = iconY - 6
    let from = appX + 108, to = appsX - 112
    cg.setStrokeColor(CGColor(red: 0.40, green: 0.39, blue: 0.86, alpha: 0.75))
    cg.setLineWidth(2.5)
    cg.setLineCap(.round)
    cg.setLineDash(phase: 0, lengths: [0.1, 9])
    cg.move(to: CGPoint(x: from, y: y))
    cg.addLine(to: CGPoint(x: to - 6, y: y))
    cg.strokePath()
    cg.setLineDash(phase: 0, lengths: [])
    cg.setLineWidth(2.5)
    cg.setLineJoin(.round)
    cg.move(to: CGPoint(x: to - 10, y: y - 9))
    cg.addLine(to: CGPoint(x: to, y: y))
    cg.addLine(to: CGPoint(x: to - 10, y: y + 9))
    cg.strokePath()

    // 文字（AppKit 绘制用的是非翻转坐标，临时翻回去）
    func text(_ s: String, size fontSize: CGFloat, weight: NSFont.Weight, alpha: CGFloat, centerY: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: NSColor(red: 0.11, green: 0.1, blue: 0.16, alpha: alpha),
            .paragraphStyle: style,
            .kern: 0.2,
        ]
        let str = NSAttributedString(string: s, attributes: attrs)
        let h = str.size().height
        cg.saveGState()
        cg.translateBy(x: 0, y: size.height)
        cg.scaleBy(x: 1, y: -1)
        str.draw(in: CGRect(x: 0, y: size.height - centerY - h / 2, width: size.width, height: h))
        cg.restoreGState()
    }
    text("拖到 Applications 文件夹即可完成安装", size: 13, weight: .medium, alpha: 0.78, centerY: 332)
    text("Drag codedog to Applications to install", size: 11, weight: .regular, alpha: 0.42, centerY: 354)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "scripts/dmg/background.tiff")
let image = NSImage(size: size)
image.addRepresentation(render(scale: 1))
image.addRepresentation(render(scale: 2))
guard let tiff = image.tiffRepresentation(using: .lzw, factor: 1) else { fatalError("tiff 编码失败") }
try tiff.write(to: out)
print("wrote \(out.path)")
