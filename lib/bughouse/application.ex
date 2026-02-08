defmodule Bughouse.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      BughouseWeb.Telemetry,
      Bughouse.Repo,
      {DNSCluster, query: Application.get_env(:bughouse, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Bughouse.PubSub},
      # Registry for game server name registration
      {Registry, keys: :unique, name: Bughouse.Games.Registry},
      # Dynamic supervisor for game servers
      {DynamicSupervisor, name: Bughouse.Games.GameSupervisor, strategy: :one_for_one},
      # Dynamic supervisor for bot engine processes (Erlang Ports)
      Bughouse.BotEngine.Supervisor,
      # Start a worker by calling: Bughouse.Worker.start_link(arg)
      # {Bughouse.Worker, arg},
      # Start to serve requests, typically the last entry
      BughouseWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Bughouse.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    BughouseWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
