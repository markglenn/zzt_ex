# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
use Mix.Config

config :zzt_ex,
  namespace: ZZTEx

# Configures the endpoint
config :zzt_ex, ZZTExWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "G0rlLIejORDAMFbi1zhsQvBVZQJBLDQOsNhpKcr4pbubF+WfbLs6q+z9JGQ2dKhT",
  render_errors: [view: ZZTExWeb.ErrorView, accepts: ~w(html json), layout: false],
  pubsub_server: ZZTEx.PubSub,
  live_view: [signing_salt: "4WzJmEGW"]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"
