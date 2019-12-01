---
title: "Auto clustering and process distribution in Elixir"
date: 2019-12-01T04:02:26+05:30
---

Writing this down because I keep coming back to solving this whenever I build and deploy
a new Elixir/Phoenix app. This article answers the following questions:

1. How to automatically form a cluster of elixir nodes.
2. How to ensure only one copy of a process runs on an elixir cluster of two or more nodes.
3. How to ensure at least one copy of a process runs on the cluster when nodes can die and restart.

The easiest way is to use two libraries:

1. [libcluster](https://github.com/bitwalker/libcluster) - for auto-clustering.
2. [swarm](https://github.com/bitwalker/swarm) - for process registration and distribution.

All you need is demonstrated in this [sample app repository on github](https://github.com/emilsoman/elixir_clustering).
Readme is pasted below for quick reference.

## How to use swarm + libcluster

Relevant lines of code from example code https://github.com/emilsoman/elixir_clustering:

1. swarm and libcluster added in mix.exs
2. A new dynamic supervisor created at `lib/my_app/dynamic_supervisor.ex`
3. `{DynamicSupervisor, strategy: :one_for_one, name: MyApp.DynamicSupervisor}` added to lib/my_app/application.ex.
4. Example GenServer created at `lib/my_app/singleton_worker.ex` to demonstrate singleton behaviour in cluster.
5. Added cluster topology config in config. See `config/dev.exs`. Use K8S, EC2 or other strategy as desired in prod.
6. Added `{Cluster.Supervisor, [Application.get_env(:libcluster, :topologies), [name: MyApp.ClusterSupervisor]]}` to supervisor.

At this point, we can test the clustering by opening two terminal tabs and running:

```
# terminal 1
iex --sname a -S mix

# terminal 2
iex --sname b -S mix
```

When node b is started, it should print this in the log in terminal 1:

```
[tracker:ensure_swarm_started_on_remote_node] nodeup b@<hostname>
```

This means nodes are now connected and libcluster works. Now we can test process distribution by swarm.

Goals:
1. Process name should be unique per node and per cluster.
2. Process should move from node a to b when we kill node a.

```
# terminal 1 (where node a is running)
Swarm.register_name(SingletonName, MyApp.DynamicSupervisor, :register, [SingletonWorker])
# Prints the following:
[swarm on a@<hostname>] [tracker:handle_call] registering SingletonName as process started by Elixir.MyApp.DynamicSupervisor.register/1 with args [SingletonWorker]
[swarm on a@<hostname>] [tracker:do_track] starting SingletonName on a@<hostname>
SingletonWorker running on :"a@<hostname>"
[swarm on a@<hostname>] [tracker:do_track] started SingletonName on a@<hostname>
{:ok, #PID<0.187.0>}

# terminal 1 again
Swarm.register_name(SingletonName, MyApp.DynamicSupervisor, :register, [SingletonWorker])
# Prints the following:
[swarm on a@<hostname>] [tracker:handle_call] registering SingletonName as process started by Elixir.MyApp.DynamicSupervisor.register/1 with args [SingletonWorker]
{:error, {:already_registered, #PID<0.187.0>}}

# terminal 2 (where node b is running)
Swarm.register_name(SingletonName, MyApp.DynamicSupervisor, :register, [SingletonWorker])
# Prints the following:
[swarm on b@<hostname>] [tracker:handle_call] registering SingletonName as process started by Elixir.MyApp.DynamicSupervisor.register/1 with args [SingletonWorker]
[swarm on b@<hostname>] [tracker:do_track] found SingletonName already registered on a@<hostname>
{:error, {:already_registered, #PID<16338.187.0>}}

# Kill node a in terminal 1, prints the following in terminal 2 (node b)
[swarm on b@<hostname>] [tracker:handle_monitor] lost connection to SingletonName (#PID<16338.187.0>) on a@<hostname>, node is down
[swarm on b@<hostname>] [tracker:nodedown] nodedown a@<hostname>
[swarm on b@<hostname>] [tracker:handle_topology_change] topology change (nodedown for a@<hostname>)
[swarm on b@<hostname>] [tracker:handle_topology_change] restarting SingletonName on b@<hostname>
[swarm on b@<hostname>] [tracker:do_track] starting SingletonName on b@<hostname>
SingletonWorker running on :"b@<hostname>"
[swarm on b@<hostname>] [tracker:do_track] started SingletonName on b@<hostname>
[swarm on b@<hostname>] [tracker:handle_topology_change] topology change complete
```

## Starting a scheduler process

Using SchedEx, creating a job that prints "Hello world" every minute:

```
schedex_child_spec = %{id: "every_minute", start: {SchedEx, :run_every, [IO, :inspect, ["Hello world"], "* * * * *"]}}
Swarm.register_name(MyAppScheduler, __MODULE__, :register, [schedex_child_spec])
```

Adding this to the supervision tree:

```
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    distributed_workers =
      %{
        id: SlashTeam.StartupSupervisor,
        restart: :transient,
        start:
        {Task, :start_link,
          [
            fn ->
              schedex_child_spec = %{id: "every_minute", start: {SchedEx, :run_every, [IO, :inspect, ["Hello world"], "* * * * *"]}}
              Swarm.register_name(MyAppScheduler, __MODULE__, :register, [schedex_child_spec])
            end
          ]}
      }

    children = [
      {Cluster.Supervisor, [Application.get_env(:libcluster, :topologies), [name: MyApp.ClusterSupervisor]]},
      {DynamicSupervisor, strategy: :one_for_one, name: MyApp.DynamicSupervisor},
      distributed_workers
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```
