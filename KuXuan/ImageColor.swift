import UIKit

/// 取图片主色：缩到 32x32 采样，排除接近纯黑/纯白的像素后取均值，
/// 这样中心光晕呈现的是专辑真实主色调，而不是封面的白边/黑边。
func dominantColor(_ image: UIImage?) -> UIColor {
    guard let image = image,
          image.cgImage != nil else {
        return UIColor(red: 0.20, green: 0.12, blue: 0.16, alpha: 1)
    }
    let size = CGSize(width: 32, height: 32)
    let renderer = UIGraphicsImageRenderer(size: size)
    let small = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: size))
    }
    guard let ctx = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8,
                              bytesPerRow: 32 * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
          let cgImg = small.cgImage,
          let data = ctx.data else { return UIColor(red: 0.20, green: 0.12, blue: 0.16, alpha: 1) }

    ctx.draw(cgImg, in: CGRect(origin: .zero, size: size))
    let buf = data.bindMemory(to: UInt8.self, capacity: 32 * 32 * 4)

    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, n: CGFloat = 0
    for y in 0..<32 {
        for x in 0..<32 {
            let i = (y * 32 + x) * 4
            let rr = CGFloat(buf[i]) / 255
            let gg = CGFloat(buf[i + 1]) / 255
            let bb = CGFloat(buf[i + 2]) / 255
            let maxc = max(rr, gg, bb)
            let minc = min(rr, gg, bb)
            // 排除接近纯黑或纯白的像素（黑边/白边）
            if maxc < 0.12 || minc > 0.92 { continue }
            r += rr; g += gg; b += bb; n += 1
        }
    }
    if n == 0 { return UIColor(red: 0.20, green: 0.12, blue: 0.16, alpha: 1) }
    return UIColor(red: r / n, green: g / n, blue: b / n, alpha: 1)
}
