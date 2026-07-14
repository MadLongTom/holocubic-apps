# AIDA Monitor

HoloCubic app that renders the **AIDA64 RemoteSensor LCD layout itself**, instead of mapping a fixed list of sensor names to a hard-coded dashboard.

The app first downloads the HTML layout from `/`, creates the corresponding 320×240 LVGL objects, and then applies live updates from `/sse`. Changing the LCD layout in AIDA64 and clicking **Apply** emits `ReLoad`; the device automatically downloads and rebuilds the layout.

## Supported RemoteSensor features

- Static labels and Simple Sensor Items
- Composite sensor label/value/unit items
- Horizontal bars, including AIDA64 foreground/background gradients
- Line Graph, Area Graph, and Histogram Graph
- Arc Gauge
- Static PNG/JPEG/BMP images and animated GIF resources served by AIDA64
- Multiple LCD pages and live `PageN` switching
- Dynamic layout reload without reinstalling the app

This target is the complete **RemoteSensor LCD** feature set. SensorPanel-only Custom Gauges are not emitted by the RemoteSensor web protocol; use AIDA64 Arc Gauge instead.

## AIDA64 setup

1. Open `File → Preferences → Hardware Monitoring → LCD`.
2. Enable RemoteSensor support.
3. Set the RemoteSensor port (this checkout defaults to `9999`).
4. Set Preview Resolution to **320 × 240**.
5. Use AIDA64's normal LCD Items editor to build the screen and pages.
6. Click **Apply**.

You should now be able to open both URLs from another LAN device:

```text
http://<aida-host>:9999/
http://<aida-host>:9999/sse
```

The included `package/holo-aida.rslcd` is only an optional starter layout. Importing it is no longer required.

## Device configuration

Open the AIDA Monitor management page from HoloCubic WebUI. It exposes:

- AIDA64 host/IP
- RemoteSensor port
- Layout path (normally `/`)
- SSE path (normally `/sse`)
- Runtime status, active page, page count, and parsed item count

The defaults in this checkout are:

```lua
config.host = "192.168.0.232"
config.port = 9999
config.layout_path = "/"
config.path = "/sse"
```

## Rendering model

RemoteSensor uses browser coordinates and does not put a canonical canvas size into the HTML response. The app therefore uses AIDA64's 320×240 preview coordinates **1:1 with no scaling**. Content outside the device viewport is clipped just like a 320×240 browser viewport.

AIDA64 font size, color, alignment, style metadata, positions, gradients, histories, scales, grids, frames, and active page are parsed. Desktop font family names and bold/italic faces such as Tahoma/Arial are mapped to fonts available in the HoloCubic firmware, so glyph metrics and face styling can differ slightly from a desktop browser.

Remote images are stored under `/sd/apps/aida_monitor/cache`. A layout `ReLoad` rebuilds the UI and refreshes the resources so replacing an image under the same filename is reflected on the device.

## Install

Upload the package directory to `/sd/apps/aida_monitor` and rescan apps. Required runtime files are:

```text
main.lua
aida_layout.lua
aida_renderer.lua
aida_client.lua
config.lua
web.lua
app.info
main.png
info.html
```

## Tests

The protocol fixture covers labels, images, composite items, bars, all three graph types, Arc Gauge, two pages, `ReLoad`, HTML entity decoding, and renderer updates:

```powershell
npx -y -p fengari-node-cli fengari aida_monitor/tests/protocol_test.lua
```

Syntax check:

```powershell
npx -y luaparse -q aida_monitor/package/aida_layout.lua
npx -y luaparse -q aida_monitor/package/aida_renderer.lua
npx -y luaparse -q aida_monitor/package/aida_client.lua
```

## Official AIDA64 references

- [RemoteSensor LCD for smartphones and tablets](https://forums.aida64.com/topic/2636-remotesensor-lcd-for-smartphones-and-tablets/)
- [External display support](https://www.aida64.com/products/features/external-display-support)
- [AIDA64 LCD Guide](https://download.aida64.com/resources/lcd/aida64_lcd_guide.pdf)
- [RemoteSensor Custom Gauge limitation](https://forums.aida64.com/topic/10160-remotesensor/)
