defmodule ZztExWeb.ErrorHTMLTest do
  use ZztExWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template, only: [render_to_string: 4]

  test "renders 404.html" do
    assert render_to_string(ZztExWeb.ErrorHTML, "404", "html", []) == "Not Found"
  end

  test "renders 500.html" do
    assert render_to_string(ZztExWeb.ErrorHTML, "500", "html", []) == "Internal Server Error"
  end
end
