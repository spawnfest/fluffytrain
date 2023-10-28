import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :fluffy_train, FluffyTrainWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "csPy/dvFRrT5NrohD0jVt7DIg+mD0X1nPtdE34EKSmNTbr9huE8OkVViawqB82tV",
  server: false

# In test we don't send emails.
config :fluffy_train, FluffyTrain.Mailer,
  adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
