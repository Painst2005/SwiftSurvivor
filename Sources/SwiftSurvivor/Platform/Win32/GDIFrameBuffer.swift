import Foundation
import WinSDK

/// Software bridge used while migrating the established GDI UI to SDL. The
/// game still renders its localized UI with GDI into a DIB, then SDL uploads
/// the completed frame as one texture. This keeps text quality intact while
/// SDL becomes the presentation backend.
final class GDIFrameBuffer {
    private var dc: HDC?
    private var bitmap: HBITMAP?
    private var previousBitmap: HGDIOBJ?
    private var width = 0
    private var height = 0

    deinit { release() }

    func ensure(width: Int, height: Int) -> HDC? {
        guard width > 0, height > 0 else { return nil }
        if dc != nil, self.width == width, self.height == height { return dc }
        release()
        guard let screenDC = GetDC(nil) else { return nil }
        defer { _ = ReleaseDC(nil, screenDC) }
        guard let newDC = CreateCompatibleDC(screenDC) else { return nil }

        var info = BITMAPINFO()
        info.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        info.bmiHeader.biWidth = LONG(width)
        info.bmiHeader.biHeight = LONG(-height)
        info.bmiHeader.biPlanes = WORD(1)
        info.bmiHeader.biBitCount = WORD(32)
        info.bmiHeader.biCompression = DWORD(BI_RGB)
        guard let newBitmap = CreateDIBSection(screenDC, &info, UINT(DIB_RGB_COLORS), nil, nil, 0) else {
            _ = DeleteDC(newDC)
            return nil
        }
        dc = newDC
        bitmap = newBitmap
        previousBitmap = SelectObject(newDC, HGDIOBJ(newBitmap))
        self.width = width
        self.height = height
        return newDC
    }

    func rgbaPixels() -> [UInt8] {
        guard width > 0, height > 0 else { return [] }
        var pixels = Array(repeating: UInt8(0), count: width * height * 4)
        guard copyRGBA(into: &pixels) else { return [] }
        return pixels
    }

    func copyRGBA(into pixels: inout [UInt8]) -> Bool {
        guard let dc, let bitmap, width > 0, height > 0 else { return false }
        var info = BITMAPINFO()
        info.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
        info.bmiHeader.biWidth = LONG(width)
        info.bmiHeader.biHeight = LONG(-height)
        info.bmiHeader.biPlanes = WORD(1)
        info.bmiHeader.biBitCount = WORD(32)
        info.bmiHeader.biCompression = DWORD(BI_RGB)
        if pixels.count != width * height * 4 {
            pixels = Array(repeating: UInt8(0), count: width * height * 4)
        }
        let copied = pixels.withUnsafeMutableBytes { bytes in
            GetDIBits(dc, bitmap, 0, UINT(height), bytes.baseAddress, &info, UINT(DIB_RGB_COLORS))
        }
        guard copied != 0 else { return false }
        // GDI stores pixels as BGRA. SDL_PIXELFORMAT_RGBA32 expects RGBA on
        // Windows, so swap channels in-place before uploading.
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let blue = pixels[index]
            pixels[index] = pixels[index + 2]
            pixels[index + 2] = blue
            pixels[index + 3] = 255
        }
        return true
    }

    func release() {
        if let dc, let previousBitmap { _ = SelectObject(dc, previousBitmap) }
        if let bitmap { _ = DeleteObject(HGDIOBJ(bitmap)) }
        if let dc { _ = DeleteDC(dc) }
        dc = nil
        bitmap = nil
        previousBitmap = nil
        width = 0
        height = 0
    }
}
