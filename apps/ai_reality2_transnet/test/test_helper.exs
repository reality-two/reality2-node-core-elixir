ExUnit.start(exclude: [:hardware, :integration, :slow])

# Define Mox mock for Transport behaviour
Mox.defmock(AiReality2Transnet.MockTransport, for: AiReality2Transnet.Transport)

# Use temp directory for hive data to avoid polluting real .hive/
Application.put_env(:ai_reality2_transnet, :hive_data_dir,
  Path.join(System.tmp_dir!(), "r2_test_hive_#{System.system_time(:second)}"))
Application.put_env(:ai_reality2_transnet, :cloud_nodes, [])
