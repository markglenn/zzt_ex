defmodule ZztExWeb.PageController do
  use ZztExWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
