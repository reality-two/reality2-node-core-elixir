ExUnit.start(exclude: [:hardware, :integration, :slow])

# Define Mox mock for Transport behaviour
Mox.defmock(Reality2Transnet.MockTransport, for: Reality2Transnet.Transport)

# Use temp directory for trust_group data to avoid polluting real .r2/
Application.put_env(:reality2_transnet, :trust_group_data_dir,
  Path.join(System.tmp_dir!(), "r2_test_trust_group_#{System.system_time(:second)}"))
Application.put_env(:reality2_transnet, :cloud_nodes, [])
