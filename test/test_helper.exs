ExUnit.start()

Code.require_file "./support/schema.exs", __DIR__
Code.require_file "./support/repo.exs", __DIR__
Code.require_file "./support/migrations.exs", __DIR__
Code.require_file "./support/model_case.exs", __DIR__

defmodule Coherence.RepoSetup do
  use ExUnit.CaseTemplate
end

TestCoherence.Repo.__adapter__.storage_down TestCoherence.Repo.config
TestCoherence.Repo.__adapter__.storage_up TestCoherence.Repo.config

{:ok, _pid} = TestCoherence.Repo.start_link
_ = Ecto.Migrator.up(TestCoherence.Repo, 0, TestCoherence.Migrations, log: false)
Process.flag(:trap_exit, true)
Ecto.Adapters.SQL.Sandbox.mode(TestCoherence.Repo, :manual)