local Web = {}
local JSON = rawget(_G, "sjson") or rawget(_G, "json")

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function normalize_path(value, fallback)
  local path = trim(value)
  if path == "" then path = fallback or "/" end
  if path:sub(1, 1) ~= "/" then path = "/" .. path end
  return path
end

local function url_decode(text)
  text = tostring(text or ""):gsub("+", " ")
  return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

local function parse_query(query)
  local result = {}
  for pair in tostring(query or ""):gmatch("([^&]+)") do
    local key, value = pair:match("^([^=]*)=(.*)$")
    result[url_decode(key or pair)] = url_decode(value or "")
  end
  return result
end

local function json_escape(text)
  return tostring(text or ""):gsub("\\", "\\\\"):gsub('"', '\\"')
    :gsub("\r", "\\r"):gsub("\n", "\\n"):gsub("\t", "\\t")
end

local function fallback_json(value)
  local kind = type(value)
  if kind == "nil" then return "null" end
  if kind == "boolean" or kind == "number" then return tostring(value) end
  if kind == "string" then return '"' .. json_escape(value) .. '"' end
  if kind ~= "table" then return '"' .. json_escape(tostring(value)) .. '"' end
  local parts = {}
  for key, item in pairs(value) do
    parts[#parts + 1] = '"' .. json_escape(key) .. '":' .. fallback_json(item)
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

local function encode_json(value)
  if JSON and JSON.encode then
    local ok, encoded = pcall(JSON.encode, value)
    if ok and encoded then return encoded end
  end
  return fallback_json(value)
end

local function response(status, content_type, body)
  return {
    status = status or "200 OK",
    type = content_type or "text/plain; charset=utf-8",
    headers = { ["cache-control"] = "no-store", ["connection"] = "close",
      ["access-control-allow-origin"] = "*" },
    body = body or "",
  }
end

local function json_response(status, value)
  return response(status, "application/json; charset=utf-8", encode_json(value))
end

local function valid_host(host)
  if host == "" or #host > 253 then return false end
  if host:find("[^%w%.%-:]") then return false end
  return true
end

local function config_text(config)
  return string.format([=[local config = {}

config.host = %q
config.port = %d
config.layout_path = %q
config.path = %q
config.vector_font_family = %q
config.vector_font_module = %q
config.vector_font_path = %q

config.timeout_ms = %d
config.reconnect_ms = %d
config.stale_ms = %d
config.watchdog_ms = %d
config.layout_retry_ms = %d
config.reload_delay_ms = %d
config.max_layout_bytes = %d
config.history_points = %d
config.cache_dir = %q
config.max_image_bytes = %d
config.max_image_pixels = %d
config.image_timeout_ms = %d
config.serial_log = %s

return config
]=],
    tostring(config.host or "192.168.0.232"),
    tonumber(config.port) or 9999,
    normalize_path(config.layout_path, "/"),
    normalize_path(config.path, "/sse"),
    tostring(config.vector_font_family or "AIDA Noto Sans SC"),
    tostring(config.vector_font_module or "/sd/apps/aida_monitor/modules/aida_font.so"),
    tostring(config.vector_font_path or "/sd/apps/aida_monitor/font/aida_noto_sans_sc.ttf"),
    tonumber(config.timeout_ms) or 7000,
    tonumber(config.reconnect_ms) or 2000,
    tonumber(config.stale_ms) or 5000,
    tonumber(config.watchdog_ms) or 1000,
    tonumber(config.layout_retry_ms) or 3000,
    tonumber(config.reload_delay_ms) or 500,
    tonumber(config.max_layout_bytes) or 196608,
    tonumber(config.history_points) or 96,
    tostring(config.cache_dir or "/sd/apps/aida_monitor/cache"),
    tonumber(config.max_image_bytes) or 262144,
    tonumber(config.max_image_pixels) or 307200,
    tonumber(config.image_timeout_ms) or 7000,
    config.serial_log == false and "false" or "true")
end

local function write_config(path, config)
  local raw = config_text(config)
  if file and file.putcontents then
    local ok, result = pcall(file.putcontents, path, raw)
    if ok and result ~= false then return true end
    return false, tostring(result)
  end
  return false, "file.putcontents unavailable"
end

local function build_html(api)
  api = tostring(api):gsub("\\", "\\\\"):gsub('"', '\\"')
  return [=[<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>AIDA RemoteSensor</title>
<style>
:root{color-scheme:dark;--bg:#080b10;--panel:#10151d;--line:#273344;--text:#edf4ff;--muted:#91a0b5;--cyan:#49b6ff;--green:#55d894;--red:#ff6b5f}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:14px/1.5 ui-monospace,SFMono-Regular,Consolas,"Microsoft YaHei",monospace}.page{width:min(920px,calc(100% - 24px));margin:auto;padding:22px 0}.head{display:flex;justify-content:space-between;gap:16px;align-items:end;margin-bottom:14px}h1{margin:0;font-size:24px}.sub{color:var(--muted);margin:3px 0 0}.grid{display:grid;grid-template-columns:1fr .86fr;gap:12px}.panel{border:1px solid var(--line);background:var(--panel);padding:16px}.panel h2{font-size:15px;margin:0 0 13px;color:var(--cyan)}.form{display:grid;gap:12px}.row{display:grid;grid-template-columns:1fr 130px;gap:10px}label{display:block;color:var(--muted);font-size:12px;margin-bottom:5px}input{width:100%;height:40px;border:1px solid var(--line);background:#090d13;color:var(--text);padding:0 10px;font:inherit;outline:none}input:focus{border-color:var(--cyan)}.font-guide{border-top:1px dashed var(--line);padding-top:12px}.font-command{display:flex;align-items:baseline;justify-content:space-between;gap:12px;border-bottom:1px solid var(--line);padding-bottom:8px}.font-command span{color:var(--muted);font-size:11px;letter-spacing:.12em}.font-command strong{color:var(--green);font-size:15px}.font-meta{display:flex;gap:7px;flex-wrap:wrap;margin:8px 0}.font-meta code{border:1px solid var(--line);background:#090d13;padding:2px 6px;font-size:11px}.font-copy{margin:6px 0;color:var(--muted);font-size:12px}.font-actions{display:flex;align-items:center;justify-content:space-between;gap:10px;margin-top:8px}.font-state{font-size:11px}.font-download{color:var(--cyan);font-size:12px;text-decoration:none;border-bottom:1px solid currentColor}button,a.button{height:40px;border:1px solid var(--line);background:#141c27;color:var(--text);padding:0 13px;font:inherit;cursor:pointer;text-decoration:none;display:inline-flex;align-items:center}.primary{background:var(--cyan);border-color:var(--cyan);color:#05111a;font-weight:800}.actions{display:flex;gap:8px;flex-wrap:wrap}.status{min-height:21px;color:var(--muted)}.status.ok{color:var(--green)}.status.err{color:var(--red)}.runtime{display:grid;grid-template-columns:repeat(4,1fr);gap:7px;margin-bottom:13px}.metric{border:1px solid var(--line);background:#090d13;padding:9px}.metric b{display:block;color:var(--cyan);font-size:18px}.metric b.warn{color:var(--red)}.metric span{color:var(--muted);font-size:11px}.steps{margin:0;padding-left:20px;color:var(--muted)}.steps li{margin:9px 0}.steps strong{color:var(--text)}code{color:var(--green);overflow-wrap:anywhere}.note{border-left:2px solid var(--cyan);padding:8px 10px;background:#0b121b;color:var(--muted)}@media(max-width:720px){.grid{grid-template-columns:1fr}.row{grid-template-columns:1fr}.head{align-items:start}.runtime{grid-template-columns:repeat(2,1fr)}.font-command,.font-actions{align-items:flex-start;flex-direction:column}}
</style></head><body><main class="page">
<header class="head"><div><h1>AIDA64 // REMOTESENSOR</h1><p class="sub">HoloCubic 动态 LCD 布局桥接</p></div><a class="button" href="/main">返回主界面</a></header>
<section class="grid"><section class="panel"><h2>&gt; CONNECTION</h2>
<div class="runtime"><div class="metric"><b id="rtStatus">--</b><span>STATUS</span></div><div class="metric"><b id="rtPage">--</b><span>PAGE</span></div><div class="metric"><b id="rtItems">--</b><span>ITEMS</span></div><div class="metric"><b id="rtImages">--</b><span>IMAGES</span></div></div>
<form class="form" id="form"><div class="row"><div><label>主机 IP / Host</label><input id="host" required placeholder="192.168.0.232"></div><div><label>RemoteSensor 端口</label><input id="port" inputmode="numeric" required placeholder="9999"></div></div><div class="row"><div><label>布局路径</label><input id="layout" value="/"></div><div><label>SSE 路径</label><input id="stream" value="/sse"></div></div><div class="font-guide"><div class="font-command"><span>AIDA64 FONT</span><strong>AIDA Noto Sans SC</strong></div><div class="font-meta"><code>6–96 PX</code><code>中文 GB2312</code><code>B / I / U / S / SHADOW</code></div><p class="font-copy">请在 AIDA64 的每个 LCD 文本项目中统一选择此字体。设备会按 AIDA64 字号即时栅格化，不再使用固定字号位图。</p><div class="font-actions"><code class="font-state" id="fontState">ENGINE // CHECKING</code><a class="font-download" href="/apps/aida_monitor/font/aida_noto_sans_sc.ttf" download>下载并安装同款 TTF</a></div></div><div class="actions"><button class="primary" type="submit">保存 · 重载布局</button><button type="button" id="openLayout">打开布局</button><button type="button" id="openStream">打开数据流</button></div><div id="status" class="status">正在读取设备状态...</div></form></section>
<aside class="panel"><h2>&gt; AIDA64 SETUP</h2><ol class="steps"><li>在 <strong>Preferences → Hardware Monitoring → LCD</strong> 启用 RemoteSensor。</li><li>端口设置为 <strong>9999</strong>，Preview Resolution 设置为 <strong>320 × 240</strong>。</li><li>直接使用 AIDA64 的 LCD Items 编辑器添加标签、图片、柱条、曲线、Arc Gauge 和页面。</li><li>点击 Apply。设备收到 <code>ReLoad</code> 后会自动重新读取整个布局。</li></ol><p class="note">设备按 320×240 原始坐标渲染，不缩放。SensorPanel 专用 Custom Gauge 不属于 RemoteSensor 协议；请使用 Arc Gauge。</p><code id="preview">http://--:9999/</code></aside></section></main>
<script>
const API="]=] .. api .. [=[";const $=id=>document.getElementById(id);let state={};
function path(v,d){v=(v||"").trim()||d;return v[0]==="/"?v:"/"+v}function base(){return "http://"+$("host").value.trim()+":"+$("port").value.trim()}function sync(){ $("preview").textContent=base()+path($("layout").value,"/") }
function tone(text,kind){$("status").textContent=text;$("status").className="status "+(kind||"")}
function bytes(n){n=Number(n)||0;return n>1048576?(n/1048576).toFixed(1)+"M":n>1024?Math.round(n/1024)+"K":n+"B"}function runtime(d){$("rtStatus").textContent=d.status||"--";$("rtPage").textContent=(d.page||0)+"/"+(d.pages||0);$("rtItems").textContent=d.items||0;let n=$("rtImages"),skip=d.images_skipped||0;n.textContent=(d.images_loaded||0)+"/"+((d.images_loaded||0)+skip);n.className=skip?"warn":"";$("fontState").textContent=d.font_loaded?("ENGINE // "+(d.font_engine||"VECTOR").toUpperCase()+" · CACHE "+bytes(d.font_cache_bytes)):"ENGINE // FALLBACK"}function apply(d){state=d;$("host").value=d.host||"";$("port").value=d.port||9999;$("layout").value=d.layout_path||"/";$("stream").value=d.path||"/sse";runtime(d);sync()}
async function load(){let r=await fetch(API+"/state?_="+Date.now(),{cache:"no-store"});if(!r.ok)throw Error("HTTP "+r.status);let d=await r.json();apply(d);let err=d.font_error?("矢量字体已回退："+d.font_error):d.image_error?("图像已安全跳过："+d.image_error):"设备状态已同步。";tone(err,(d.font_error||d.image_error)?"err":"ok")}
$("form").addEventListener("submit",async e=>{e.preventDefault();try{tone("正在保存并重新读取布局...");let q=new URLSearchParams({host:$("host").value.trim(),port:$("port").value.trim(),layout_path:path($("layout").value,"/"),path:path($("stream").value,"/sse")});let r=await fetch(API+"/save?"+q,{cache:"no-store"});let d=await r.json();if(!r.ok||!d.ok)throw Error(d.error||"保存失败");apply(d);tone("已保存，正在用矢量字体重载布局。","ok")}catch(err){tone(err.message,"err")}});
$("openLayout").onclick=()=>window.open(base()+path($("layout").value,"/"),"_blank");$("openStream").onclick=()=>window.open(base()+path($("stream").value,"/sse"),"_blank");["host","port","layout","stream"].forEach(id=>$(id).addEventListener("input",sync));load().catch(e=>tone(e.message,"err"));setInterval(()=>fetch(API+"/state?_="+Date.now(),{cache:"no-store"}).then(r=>r.json()).then(runtime).catch(()=>{}),3000);
</script></body></html>]=]
end

function Web.new(opts)
  opts = opts or {}
  local self = {
    config = opts.config or {}, config_path = opts.config_path,
    route_base = opts.route_base or "/aida_monitor", restart = opts.restart,
    runtime_state = opts.state, routes = {}, started = false,
  }
  self.api_prefix = self.route_base .. "/api"

  function self:snapshot(ok, message)
    local runtime = self.runtime_state and self.runtime_state() or {}
    local host = tostring(self.config.host or "")
    local port = tonumber(self.config.port) or 9999
    return {
      ok = ok ~= false, message = message or "", host = host, port = port,
      layout_path = normalize_path(self.config.layout_path, "/"),
      path = normalize_path(self.config.path, "/sse"),
      font = tostring(self.config.vector_font_family or "AIDA Noto Sans SC"),
      layout_url = "http://" .. host .. ":" .. port .. normalize_path(self.config.layout_path, "/"),
      stream_url = "http://" .. host .. ":" .. port .. normalize_path(self.config.path, "/sse"),
      status = runtime.status or "STARTING", detail = runtime.detail or "",
      page = runtime.page or 0, pages = runtime.pages or 0, items = runtime.items or 0,
      counts = runtime.counts or {}, last_event_ms = runtime.last_event_ms or 0,
      images_loaded = runtime.images_loaded or 0,
      images_skipped = runtime.images_skipped or 0,
      image_error = runtime.image_error or "",
      font_loaded = runtime.font_loaded ~= false,
      font_engine = runtime.font_engine or "firmware fallback",
      font_error = runtime.font_error or "",
      font_bytes = runtime.font_bytes or 0,
      font_cache_bytes = runtime.font_cache_bytes or 0,
      font_cache_entries = runtime.font_cache_entries or 0,
      font_renders = runtime.font_renders or 0,
      font_missing_glyphs = runtime.font_missing_glyphs or 0,
      internal_free = runtime.internal_free or 0,
      psram_free = runtime.psram_free or 0,
      psram_largest = runtime.psram_largest or 0,
    }
  end

  function self:register(method, route, handler)
    if not httpd or not httpd.dynamic then return false end
    local ok, err = pcall(httpd.dynamic, method, route, handler)
    if ok and not err then self.routes[#self.routes + 1] = { method = method, route = route } return true end
    return false
  end

  function self:save(req)
    local query = parse_query(req and req.query or "")
    local host, port = trim(query.host), tonumber(query.port)
    if not valid_host(host) then return json_response("400 Bad Request", { ok = false, error = "主机地址无效" }) end
    if not port or port < 1 or port > 65535 then return json_response("400 Bad Request", { ok = false, error = "端口需为 1–65535" }) end
    self.config.host, self.config.port = host, math.floor(port)
    self.config.layout_path = normalize_path(query.layout_path, "/")
    self.config.path = normalize_path(query.path, "/sse")
    local ok, err = write_config(self.config_path, self.config)
    if not ok then return json_response("500 Internal Server Error", { ok = false, error = "配置写入失败: " .. tostring(err) }) end
    if self.restart then pcall(self.restart) end
    return json_response("200 OK", self:snapshot(true, "saved"))
  end

  function self:start()
    if self.started or not httpd or not httpd.start then return end
    pcall(httpd.start, { webroot = "/sd", auto_index = httpd.INDEX_NONE, max_handlers = 32 })
    local page_html = build_html(self.api_prefix)
    self:register(httpd.GET, self.route_base, function() return response("200 OK", "text/html; charset=utf-8", page_html) end)
    self:register(httpd.GET, self.route_base .. "/", function() return response("200 OK", "text/html; charset=utf-8", page_html) end)
    self:register(httpd.GET, self.api_prefix .. "/state", function() return json_response("200 OK", self:snapshot(true, "loaded")) end)
    self:register(httpd.GET, self.api_prefix .. "/save", function(req) return self:save(req) end)
    self:register(httpd.GET, self.api_prefix .. "/health", function() return response("200 OK", "text/plain", "ok") end)
    self.started = true
  end

  function self:stop()
    if httpd and httpd.unregister then
      for i = #self.routes, 1, -1 do pcall(httpd.unregister, self.routes[i].method, self.routes[i].route) end
    end
    self.routes, self.started = {}, false
  end
  return self
end

return Web
