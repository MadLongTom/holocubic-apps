local config = {}

-- AIDA64 RemoteSensor server on the Windows host.
config.host = "192.168.0.232"
config.port = 9999
config.layout_path = "/"
config.path = "/sse"

config.timeout_ms = 7000
config.reconnect_ms = 2000
config.stale_ms = 5000
config.watchdog_ms = 1000
config.layout_retry_ms = 3000
config.reload_delay_ms = 500
config.max_layout_bytes = 196608
config.history_points = 96
config.cache_dir = "/sd/apps/aida_monitor/cache"
config.max_image_bytes = 262144
config.max_image_pixels = 307200
config.image_timeout_ms = 7000
config.serial_log = true

return config
