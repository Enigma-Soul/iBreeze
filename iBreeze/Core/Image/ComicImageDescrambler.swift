import CoreGraphics
import UIKit

/// 禁漫图片的宿主侧反混淆。
///
/// 禁漫返回的图是按块纵向打乱的，插件里没有还原逻辑（Breeze 同样放在宿主侧做），
/// 宿主必须把块逆序拼回才能看到正常画面。算法与 Breeze 的
/// `decode/segmentation.rs` 保持一致：
///
/// 1. 由章节 id 与图片文件名算出分块数 num；
/// 2. 把图纵向等分成 num 块（最后一块吃掉余数）；
/// 3. 逆序写回。
enum ComicImageDescrambler {
    /// 禁漫插件 uuid：与 Breeze 一样按插件硬编码
    private static let jinshanPluginUUID = "bf99008d-010b-4f17-ac7c-61a9b57dc3d9"

    /// 低于这个章节 id 的图不打乱
    private static let scrambleID = 220980

    static func needsDescrambling(pluginUUID: String) -> Bool {
        pluginUUID == jinshanPluginUUID
    }

    /// 还原打乱；不需要还原或失败时返回原图
    static func descramble(_ image: UIImage, chapterID: String, url: String) -> UIImage {
        guard let epsID = Int(chapterID), let source = image.cgImage else { return image }

        let count = segmentationCount(epsID: epsID, pictureName: pictureName(from: url))
        guard count > 1 else { return image }

        let width = source.width
        let height = source.height
        let blockHeight = height / count
        guard blockHeight > 0 else { return image }

        let remainder = height % count
        let colorSpace = source.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        // CGContext 原点在左下：从顶边往下排，所以第一块放在 y = height - blockHeight
        var top = height
        for index in stride(from: count - 1, through: 0, by: -1) {
            let start = index * blockHeight
            let end = index == count - 1 ? start + blockHeight + remainder : start + blockHeight
            let bandHeight = end - start
            guard bandHeight > 0 else { continue }

            guard let band = source.cropping(to: CGRect(x: 0, y: start, width: width, height: bandHeight)) else {
                return image
            }

            top -= bandHeight
            context.draw(band, in: CGRect(x: 0, y: top, width: width, height: bandHeight))
        }

        guard let restored = context.makeImage() else { return image }
        return UIImage(cgImage: restored)
    }

    /// 分块数：与 Breeze 的 `get_segmentation_num` 一致
    private static func segmentationCount(epsID: Int, pictureName: String) -> Int {
        if epsID < scrambleID { return 0 }
        if epsID < 268_850 { return 10 }

        let digest = PluginCrypto.hex(PluginCrypto.digest(.md5, Data("\(epsID)\(pictureName)".utf8)))
        guard let lastCharacter = digest.last, let ascii = lastCharacter.asciiValue else { return 0 }

        let value = Int(ascii)
        return epsID > 421_926 ? (value % 8) * 2 + 2 : (value % 10) * 2 + 2
    }

    /// 图片名：URL 最后一段去掉扩展名
    private static func pictureName(from url: String) -> String {
        let fileName = url.split(separator: "/").last.map(String.init) ?? ""
        return fileName.split(separator: ".").first.map(String.init) ?? ""
    }
}
