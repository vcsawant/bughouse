defmodule BughouseWeb.PageController do
  use BughouseWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
