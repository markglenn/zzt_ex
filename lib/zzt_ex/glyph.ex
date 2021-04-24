defmodule ZZTEx.Glyph do
  @doc "Convert a CP437 glyph byte to a unicode character"
  @spec to_unicode(byte) :: char
  def to_unicode(0x0A), do: 0x25D9
  def to_unicode(0x0C), do: 0x2640
  def to_unicode(0x80), do: 0x00C7
  def to_unicode(0x81), do: 0x00FC
  def to_unicode(0x82), do: 0x00E9
  def to_unicode(0x83), do: 0x00E2
  def to_unicode(0x84), do: 0x00E4
  def to_unicode(0x85), do: 0x00E0
  def to_unicode(0x86), do: 0x00E5
  def to_unicode(0x87), do: 0x00E7
  def to_unicode(0x88), do: 0x00EA
  def to_unicode(0x89), do: 0x00EB
  def to_unicode(0x8A), do: 0x00E8
  def to_unicode(0x8B), do: 0x00EF
  def to_unicode(0x8C), do: 0x00EE
  def to_unicode(0x8D), do: 0x00EC
  def to_unicode(0x8E), do: 0x00C4
  def to_unicode(0x8F), do: 0x00C5
  def to_unicode(0x90), do: 0x00C9
  def to_unicode(0x91), do: 0x00E6
  def to_unicode(0x92), do: 0x00C6
  def to_unicode(0x93), do: 0x00F4
  def to_unicode(0x94), do: 0x00F6
  def to_unicode(0x95), do: 0x00F2
  def to_unicode(0x96), do: 0x00FB
  def to_unicode(0x97), do: 0x00F9
  def to_unicode(0x98), do: 0x00FF
  def to_unicode(0x99), do: 0x00D6
  def to_unicode(0x9A), do: 0x00DC
  def to_unicode(0x9B), do: 0x00A2
  def to_unicode(0x9C), do: 0x00A3
  def to_unicode(0x9D), do: 0x00A5
  def to_unicode(0x9E), do: 0x20A7
  def to_unicode(0x9F), do: 0x0192
  def to_unicode(0xA0), do: 0x00E1
  def to_unicode(0xA1), do: 0x00ED
  def to_unicode(0xA2), do: 0x00F3
  def to_unicode(0xA3), do: 0x00FA
  def to_unicode(0xA4), do: 0x00F1
  def to_unicode(0xA5), do: 0x00D1
  def to_unicode(0xA6), do: 0x00AA
  def to_unicode(0xA7), do: 0x00BA
  def to_unicode(0xA8), do: 0x00BF
  def to_unicode(0xA9), do: 0x2310
  def to_unicode(0xAA), do: 0x00AC
  def to_unicode(0xAB), do: 0x00BD
  def to_unicode(0xAC), do: 0x00BC
  def to_unicode(0xAD), do: 0x00A1
  def to_unicode(0xAE), do: 0x00AB
  def to_unicode(0xAF), do: 0x00BB
  def to_unicode(0xB0), do: 0x2591
  def to_unicode(0xB1), do: 0x2592
  def to_unicode(0xB2), do: 0x2593
  def to_unicode(0xB3), do: 0x2502
  def to_unicode(0xB4), do: 0x2524
  def to_unicode(0xB5), do: 0x2561
  def to_unicode(0xB6), do: 0x2562
  def to_unicode(0xB7), do: 0x2556
  def to_unicode(0xB8), do: 0x2555
  def to_unicode(0xB9), do: 0x2563
  def to_unicode(0xBA), do: 0x2551
  def to_unicode(0xBB), do: 0x2557
  def to_unicode(0xBC), do: 0x255D
  def to_unicode(0xBD), do: 0x255C
  def to_unicode(0xBE), do: 0x255B
  def to_unicode(0xBF), do: 0x2510
  def to_unicode(0xC0), do: 0x2514
  def to_unicode(0xC1), do: 0x2534
  def to_unicode(0xC2), do: 0x252C
  def to_unicode(0xC3), do: 0x251C
  def to_unicode(0xC4), do: 0x2500
  def to_unicode(0xC5), do: 0x253C
  def to_unicode(0xC6), do: 0x255E
  def to_unicode(0xC7), do: 0x255F
  def to_unicode(0xC8), do: 0x255A
  def to_unicode(0xC9), do: 0x2554
  def to_unicode(0xCA), do: 0x2569
  def to_unicode(0xCB), do: 0x2566
  def to_unicode(0xCC), do: 0x2560
  def to_unicode(0xCD), do: 0x2550
  def to_unicode(0xCE), do: 0x256C
  def to_unicode(0xCF), do: 0x2567
  def to_unicode(0xD0), do: 0x2568
  def to_unicode(0xD1), do: 0x2564
  def to_unicode(0xD2), do: 0x2565
  def to_unicode(0xD3), do: 0x2559
  def to_unicode(0xD4), do: 0x2558
  def to_unicode(0xD5), do: 0x2552
  def to_unicode(0xD6), do: 0x2553
  def to_unicode(0xD7), do: 0x256B
  def to_unicode(0xD8), do: 0x256A
  def to_unicode(0xD9), do: 0x2518
  def to_unicode(0xDA), do: 0x250C
  def to_unicode(0xDB), do: 0x2588
  def to_unicode(0xDC), do: 0x2584
  def to_unicode(0xDD), do: 0x258C
  def to_unicode(0xDE), do: 0x2590
  def to_unicode(0xDF), do: 0x2580
  def to_unicode(0xE0), do: 0x03B1
  def to_unicode(0xE1), do: 0x00DF
  def to_unicode(0xE2), do: 0x0393
  def to_unicode(0xE3), do: 0x03C0
  def to_unicode(0xE4), do: 0x03A3
  def to_unicode(0xE5), do: 0x03C3
  def to_unicode(0xE6), do: 0x00B5
  def to_unicode(0xE7), do: 0x03C4
  def to_unicode(0xE8), do: 0x03A6
  def to_unicode(0xE9), do: 0x0398
  def to_unicode(0xEA), do: 0x03A9
  def to_unicode(0xEB), do: 0x03B4
  def to_unicode(0xEC), do: 0x221E
  def to_unicode(0xED), do: 0x03C6
  def to_unicode(0xEE), do: 0x03B5
  def to_unicode(0xEF), do: 0x2229
  def to_unicode(0xF0), do: 0x2261
  def to_unicode(0xF1), do: 0x00B1
  def to_unicode(0xF2), do: 0x2265
  def to_unicode(0xF3), do: 0x2264
  def to_unicode(0xF4), do: 0x2320
  def to_unicode(0xF5), do: 0x2321
  def to_unicode(0xF6), do: 0x00F7
  def to_unicode(0xF7), do: 0x2248
  def to_unicode(0xF8), do: 0x00B0
  def to_unicode(0xF9), do: 0x2219
  def to_unicode(0xFA), do: 0x00B7
  def to_unicode(0xFB), do: 0x221A
  def to_unicode(0xFC), do: 0x207F
  def to_unicode(0xFD), do: 0x00B2
  def to_unicode(0xFE), do: 0x25A0
  def to_unicode(0xFF), do: 0x00A0
  def to_unicode(c), do: c
end
