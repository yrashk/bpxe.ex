receive_timeout = if System.get_env("CI"), do: 5000, else: 500
refute_receive_timeout = if System.get_env("CI"), do: 5000, else: 500
ExUnit.configure(assert_receive_timeout: receive_timeout, refute_receive_timeout: refute_receive_timeout)
ExUnit.start()
