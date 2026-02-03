ExUnit.start(exclude: [:hardware, :integration, :slow])

# Define Mox mock for Transport behaviour
Mox.defmock(Reality2Transnet.MockTransport, for: Reality2Transnet.Transport)

# Use temp directory for hive data to avoid polluting real .hive/
Application.put_env(:reality2_transnet, :hive_data_dir,
  Path.join(System.tmp_dir!(), "r2_test_hive_#{System.system_time(:second)}"))
Application.put_env(:reality2_transnet, :cloud_nodes, [])
