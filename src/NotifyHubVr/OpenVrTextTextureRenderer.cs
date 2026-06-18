using System.ComponentModel;
using System.Runtime.InteropServices;

namespace NotifyHubVr;

internal sealed record OpenVrOverlaySettings(int FontSize, string Position)
{
    public static OpenVrOverlaySettings FromConfig(AppConfig config)
    {
        return new OpenVrOverlaySettings(
            Math.Clamp(config.FontSize, 18, 56),
            string.IsNullOrWhiteSpace(config.OverlayPosition) ? "upper-right" : config.OverlayPosition.Trim().ToLowerInvariant());
    }
}

internal static class OpenVrTextTextureRenderer
{
    public const uint Width = 768;
    public const uint Height = 256;
    public const uint BytesPerPixel = 4;

    public static byte[] Render(NotificationMessage message, OpenVrOverlaySettings settings)
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("OpenVR text texture rendering requires Windows GDI.");
        }

        return Win32TextTextureRenderer.Render(message, settings.FontSize);
    }
}

internal static class Win32TextTextureRenderer
{
    private const int Width = (int)OpenVrTextTextureRenderer.Width;
    private const int Height = (int)OpenVrTextTextureRenderer.Height;
    private const int BytesPerPixel = (int)OpenVrTextTextureRenderer.BytesPerPixel;
    private const int BiRgb = 0;
    private const int DibRgbColors = 0;
    private const int Transparent = 1;
    private const uint DefaultCharset = 1;
    private const uint OutDefaultPrecision = 0;
    private const uint ClipDefaultPrecision = 0;
    private const uint CleartypeQuality = 5;
    private const uint DefaultPitch = 0;
    private const int FontWeightMedium = 500;
    private const int FontWeightBold = 700;
    private const uint DrawSingleLine = 0x00000020 | 0x00008000 | 0x00000800;
    private const uint DrawWrapped = 0x00000010 | 0x00008000 | 0x00000800 | 0x00002000;
    private const string FontFace = "Yu Gothic UI";

    public static byte[] Render(NotificationMessage message, int fontSize)
    {
        var screenDc = GetDC(IntPtr.Zero);
        if (screenDc == IntPtr.Zero)
        {
            throw NewWin32Exception("GetDC");
        }

        var memoryDc = IntPtr.Zero;
        var bitmap = IntPtr.Zero;
        var previousBitmap = IntPtr.Zero;
        var backgroundBrush = IntPtr.Zero;
        var accentBrush = IntPtr.Zero;
        var borderBrush = IntPtr.Zero;
        var titleFont = IntPtr.Zero;
        var bodyFont = IntPtr.Zero;

        try
        {
            memoryDc = CreateCompatibleDC(screenDc);
            if (memoryDc == IntPtr.Zero)
            {
                throw NewWin32Exception("CreateCompatibleDC");
            }

            var bitmapInfo = CreateBitmapInfo();
            bitmap = CreateDIBSection(memoryDc, ref bitmapInfo, DibRgbColors, out var bits, IntPtr.Zero, 0);
            if (bitmap == IntPtr.Zero || bits == IntPtr.Zero)
            {
                throw NewWin32Exception("CreateDIBSection");
            }

            previousBitmap = SelectObject(memoryDc, bitmap);
            if (previousBitmap == IntPtr.Zero)
            {
                throw NewWin32Exception("SelectObject(bitmap)");
            }

            var accent = AccentForLevel(message.Level);
            backgroundBrush = CreateBrush(new Rgb(14, 18, 25));
            accentBrush = CreateBrush(accent);
            borderBrush = CreateBrush(new Rgb(58, 70, 82));

            Fill(memoryDc, new Rect(0, 0, Width, Height), backgroundBrush);
            Fill(memoryDc, new Rect(0, 0, 10, Height), accentBrush);
            Fill(memoryDc, new Rect(0, 0, Width, 3), borderBrush);
            Fill(memoryDc, new Rect(0, Height - 3, Width, Height), borderBrush);
            Fill(memoryDc, new Rect(0, 0, 3, Height), borderBrush);
            Fill(memoryDc, new Rect(Width - 3, 0, Width, Height), borderBrush);

            _ = SetBkMode(memoryDc, Transparent);

            titleFont = CreateFont(Math.Max(18, fontSize - 4), FontWeightBold);
            bodyFont = CreateFont(fontSize, FontWeightMedium);

            var top = string.IsNullOrWhiteSpace(message.Title) ? 42 : 24;
            const int left = 34;
            const int right = Width - 30;

            if (!string.IsNullOrWhiteSpace(message.Title))
            {
                SelectFontAndDraw(
                    memoryDc,
                    titleFont,
                    new Rgb(194, 234, 255),
                    message.Title,
                    new Rect(left, top, right, top + fontSize + 8),
                    DrawSingleLine);
                top += fontSize + 18;
            }

            SelectFontAndDraw(
                memoryDc,
                bodyFont,
                new Rgb(248, 250, 252),
                message.Body,
                new Rect(left, top, right, Height - 24),
                DrawWrapped);

            var bgra = new byte[checked(Width * Height * BytesPerPixel)];
            Marshal.Copy(bits, bgra, 0, bgra.Length);
            return ConvertBgraToRgba(bgra);
        }
        finally
        {
            if (titleFont != IntPtr.Zero)
            {
                _ = DeleteObject(titleFont);
            }

            if (bodyFont != IntPtr.Zero)
            {
                _ = DeleteObject(bodyFont);
            }

            if (backgroundBrush != IntPtr.Zero)
            {
                _ = DeleteObject(backgroundBrush);
            }

            if (accentBrush != IntPtr.Zero)
            {
                _ = DeleteObject(accentBrush);
            }

            if (borderBrush != IntPtr.Zero)
            {
                _ = DeleteObject(borderBrush);
            }

            if (previousBitmap != IntPtr.Zero && memoryDc != IntPtr.Zero)
            {
                _ = SelectObject(memoryDc, previousBitmap);
            }

            if (bitmap != IntPtr.Zero)
            {
                _ = DeleteObject(bitmap);
            }

            if (memoryDc != IntPtr.Zero)
            {
                _ = DeleteDC(memoryDc);
            }

            _ = ReleaseDC(IntPtr.Zero, screenDc);
        }
    }

    private static BitmapInfo CreateBitmapInfo()
    {
        return new BitmapInfo
        {
            Header = new BitmapInfoHeader
            {
                Size = (uint)Marshal.SizeOf<BitmapInfoHeader>(),
                Width = Width,
                Height = -Height,
                Planes = 1,
                BitCount = 32,
                Compression = BiRgb,
                SizeImage = Width * Height * BytesPerPixel,
            },
        };
    }

    private static byte[] ConvertBgraToRgba(byte[] bgra)
    {
        var rgba = new byte[bgra.Length];
        for (var i = 0; i < bgra.Length; i += BytesPerPixel)
        {
            rgba[i + 0] = bgra[i + 2];
            rgba[i + 1] = bgra[i + 1];
            rgba[i + 2] = bgra[i + 0];
            rgba[i + 3] = 255;
        }

        return rgba;
    }

    private static void SelectFontAndDraw(IntPtr dc, IntPtr font, Rgb color, string text, Rect rect, uint format)
    {
        var previousFont = SelectObject(dc, font);
        if (previousFont == IntPtr.Zero)
        {
            throw NewWin32Exception("SelectObject(font)");
        }

        try
        {
            _ = SetTextColor(dc, color.ToColorRef());
            if (DrawText(dc, text, -1, ref rect, format) == 0)
            {
                throw NewWin32Exception("DrawText");
            }
        }
        finally
        {
            _ = SelectObject(dc, previousFont);
        }
    }

    private static IntPtr CreateFont(int pixelHeight, int weight)
    {
        var font = CreateFont(
            -pixelHeight,
            0,
            0,
            0,
            weight,
            0,
            0,
            0,
            DefaultCharset,
            OutDefaultPrecision,
            ClipDefaultPrecision,
            CleartypeQuality,
            DefaultPitch,
            FontFace);

        return font == IntPtr.Zero ? throw NewWin32Exception("CreateFont") : font;
    }

    private static IntPtr CreateBrush(Rgb color)
    {
        var brush = CreateSolidBrush(color.ToColorRef());
        return brush == IntPtr.Zero ? throw NewWin32Exception("CreateSolidBrush") : brush;
    }

    private static void Fill(IntPtr dc, Rect rect, IntPtr brush)
    {
        if (FillRect(dc, ref rect, brush) == 0)
        {
            throw NewWin32Exception("FillRect");
        }
    }

    private static Rgb AccentForLevel(string level)
    {
        return level.Trim().ToLowerInvariant() switch
        {
            "error" or "danger" => new Rgb(239, 68, 68),
            "warn" or "warning" => new Rgb(245, 158, 11),
            "success" => new Rgb(34, 197, 94),
            _ => new Rgb(45, 212, 191),
        };
    }

    private static Win32Exception NewWin32Exception(string operation)
    {
        return new Win32Exception(Marshal.GetLastWin32Error(), $"Win32 {operation} failed.");
    }

    private readonly record struct Rgb(byte Red, byte Green, byte Blue)
    {
        public int ToColorRef()
        {
            return Red | (Green << 8) | (Blue << 16);
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BitmapInfo
    {
        public BitmapInfoHeader Header;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct BitmapInfoHeader
    {
        public uint Size;
        public int Width;
        public int Height;
        public ushort Planes;
        public ushort BitCount;
        public int Compression;
        public int SizeImage;
        public int XPelsPerMeter;
        public int YPelsPerMeter;
        public uint ClrUsed;
        public uint ClrImportant;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public Rect(int left, int top, int right, int bottom)
        {
            Left = left;
            Top = top;
            Right = right;
            Bottom = bottom;
        }

        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr GetDC(IntPtr hwnd);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern int ReleaseDC(IntPtr hwnd, IntPtr hdc);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern int DrawText(IntPtr hdc, string text, int textLength, ref Rect rect, uint format);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern int FillRect(IntPtr hdc, ref Rect rect, IntPtr brush);

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern IntPtr CreateCompatibleDC(IntPtr hdc);

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern bool DeleteDC(IntPtr hdc);

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern IntPtr CreateDIBSection(
        IntPtr hdc,
        ref BitmapInfo bitmapInfo,
        uint usage,
        out IntPtr bits,
        IntPtr section,
        uint offset);

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern IntPtr SelectObject(IntPtr hdc, IntPtr obj);

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern bool DeleteObject(IntPtr obj);

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern int SetBkMode(IntPtr hdc, int mode);

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern int SetTextColor(IntPtr hdc, int color);

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern IntPtr CreateSolidBrush(int color);

    [DllImport("gdi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateFont(
        int height,
        int width,
        int escapement,
        int orientation,
        int weight,
        uint italic,
        uint underline,
        uint strikeOut,
        uint charSet,
        uint outputPrecision,
        uint clipPrecision,
        uint quality,
        uint pitchAndFamily,
        string faceName);
}
