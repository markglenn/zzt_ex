defmodule ZztEx.Zzt.ScrollTest do
  use ExUnit.Case, async: true

  alias ZztEx.Zzt.Scroll

  test "parses a simple scroll into a title and visible lines" do
    code = "@Sign\rHello, world!\rPress any key."

    result = Scroll.parse(code)

    assert result.title == "Sign"
    assert result.lines == ["Hello, world!", "Press any key."]
  end

  test "a scroll without a @Name header falls back to 'Scroll'" do
    result = Scroll.parse("Just some text.\rAnother line.")

    assert result.title == "Scroll"
    assert result.lines == ["Just some text.", "Another line."]
  end

  test "ZZT-OOP control lines (#/@/:/?//) are stripped from the body" do
    code =
      "@Title\r" <>
        ":start\r" <>
        "Welcome, adventurer!\r" <>
        "#zap touch\r" <>
        "/n/n/n\r" <>
        "?left\r" <>
        "$Highlighted line\r" <>
        "#end"

    result = Scroll.parse(code)
    assert result.title == "Title"
    assert result.lines == ["Welcome, adventurer!", "$Highlighted line"]
  end

  test "decodes CP437 bytes above 0x7E into their Unicode equivalents" do
    # 0xB2 = CP437 ▓ (U+2593), 0xE9 = CP437 Θ (U+0398).
    code = <<"Heavy shade: ", 0xB2, "\r", "Theta: ", 0xE9>>

    result = Scroll.parse(code)

    assert result.lines == [
             "Heavy shade: " <> <<0x2593::utf8>>,
             "Theta: " <> <<0x0398::utf8>>
           ]
  end

  test "trailing NUL from the OOP code body is trimmed (but empty lines stay)" do
    # ZZT scrolls are CR-terminated, so a trailing empty line is normal.
    code = "@Title\rHello\r" <> <<0>>
    assert Scroll.parse(code).lines == ["Hello", ""]
  end
end
