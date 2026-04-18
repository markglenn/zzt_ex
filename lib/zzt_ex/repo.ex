defmodule ZztEx.Repo do
  use Ecto.Repo,
    otp_app: :zzt_ex,
    adapter: Ecto.Adapters.Postgres
end
