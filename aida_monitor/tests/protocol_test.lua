local Layout = dofile("aida_monitor/package/aida_layout.lua")
local AidaClient = dofile("aida_monitor/package/aida_client.lua")

local html = dofile("aida_monitor/tests/fixtures/remotesensor-layout.lua")

local model, err = Layout.parse(html)
assert(model, err)
assert(model.background == 0x101010, "background")
assert(model.page_count == 2, "page count")
assert(model.item_count == 9, "item count: " .. tostring(model.item_count))
assert(model.counts.label == 2, "labels")
assert(model.counts.image == 1, "images")
assert(model.counts.sensor == 1, "sensors")
assert(model.counts.graph == 3, "graphs")
assert(model.counts.arc == 1, "arcs")
assert(model.counts.simple == 1, "simple")
assert(model.items.Gph4.params.graph_type == "LG", "line graph")
assert(model.items.Gph5.params.graph_type == "AG", "area graph")
assert(model.items.Gph6.params.graph_type == "HG", "hist graph")
assert(model.items.Arc7.params.thickness == 10, "arc thickness")
assert(model.items.Image1.src == "probe.png", "image source")
assert(model.items.Image1.geometry.w == 16 and model.items.Image1.geometry.h == 16, "image display size")
assert(model.items.Label1.text_style.font.size == 16, "point size converted to pixels")
assert(model.items.Label1.text_style.font.bold and model.items.Label1.text_style.font.italic, "font styles")
assert(model.items.Label1.text_style.underline and model.items.Label1.text_style.strike, "decorations")
assert(model.items.Label1.text_style.shadow.x == 2 and model.items.Label1.text_style.shadow.blur == 1, "shadow")
assert(model.items.Gph4.params.font_size == 11, "graph point size converted to pixels")

local payload = "Page0{|}SIV3|42{|}Bar3p|42|#202020,#151515|#00FF00,#00AA00{|}Gph4p|42|{|}Gph5p|42|{|}Gph6p|42|{|}Arc7p|42|42|#202020|#00FF00{|}Simple11|CPU Temp 48&deg;C{|}"
local sample = AidaClient.parse_remote_payload(payload)
assert(sample.page == 1, "active page")
assert(#sample.updates == 7, "update count: " .. tostring(#sample.updates))
assert(sample.updates[1].id == "SIV3" and sample.updates[1].text == "42", "value update")
assert(sample.updates[2].kind == "bar" and sample.updates[2].percent == 42, "bar update")
assert(sample.updates[6].kind == "arc" and sample.updates[6].active_color == 0x00FF00, "arc update")
assert(sample.updates[7].text == "CPU Temp 48°C", "entity decode")
assert(AidaClient.parse_remote_payload("ReLoad").control == "ReLoad", "reload control")
assert(AidaClient.parse_remote_payload("Page1{|}Simple11|OK{|}").page == 2, "second page")

local captured_vector_options = nil
package.preload["aida_font_test"] = function()
  return {
    open = function(path) return path == "/font.ttf" end,
    render = function(_, width, height, _, _, _, _, options)
      captured_vector_options = options
      return string.rep("\0", width * height * 2)
    end,
    stats = function() return { loaded = true, engine = "stb_truetype" } end,
  }
end
local VectorFont = dofile("aida_monitor/package/aida_vector_font.lua")
local vector_wrapper = VectorFont.new({ vector_font_module = "aida_font_test", vector_font_path = "/font.ttf" })
assert(vector_wrapper.ready, vector_wrapper.error)
local vector_buffer = vector_wrapper:render("中文", 32, 18, model.items.Label1.text_style, 0, 0x00FF00)
assert(#vector_buffer == 32 * 18 * 2, "vector wrapper buffer")
assert(captured_vector_options.bold and captured_vector_options.italic, "vector wrapper face styles")
assert(captured_vector_options.underline and captured_vector_options.strike, "vector wrapper decorations")
assert(captured_vector_options.shadow_dx == 2 and captured_vector_options.shadow_blur == 1, "vector wrapper shadow")

local next_object = 10
local function object()
  next_object = next_object + 1
  return next_object
end
LV_PART_MAIN, LV_STATE_DEFAULT = 0, 0
LV_OBJ_FLAG_SCROLLABLE, LV_OBJ_FLAG_HIDDEN = 1, 2
LV_IMG_CF_TRUE_COLOR = 1
LV_IMG_CF_TRUE_COLOR_CHROMA_KEYED = 2
LV_COLOR_CHROMA_KEY = 0x00FF00
lv_scr_act = function() return 1 end
lv_obj_create = function() return object() end
lv_label_create = function() return object() end
lv_canvas_create = function() return object() end
lv_obj_clean = function() end
lv_obj_set_pos = function() end
lv_obj_set_size = function() end
lv_obj_set_width = function() end
lv_obj_set_style_bg_color = function() end
lv_obj_set_style_bg_opa = function() end
lv_obj_set_style_border_width = function() end
lv_obj_set_style_radius = function() end
lv_obj_set_style_pad_all = function() end
lv_obj_set_style_text_color = function() end
lv_obj_set_style_text_opa = function() end
lv_obj_set_style_text_font = function() end
lv_obj_set_style_text_align = function() end
lv_obj_set_style_bg_grad_color = function() end
lv_obj_set_style_bg_grad_dir = function() end
lv_obj_set_style_bg_main_stop = function() end
lv_obj_set_style_bg_grad_stop = function() end
lv_obj_clear_flag = function() end
lv_obj_add_flag = function() end
lv_label_set_text = function() end
lv_canvas_fill_bg = function() end
lv_canvas_draw_rect = function() end
lv_canvas_draw_line = function() end
lv_canvas_draw_text = function() end
lv_canvas_draw_arc = function() end
lv_canvas_blit_rgb565 = function(_, _, _, width, height, data)
  assert(#data == width * height * 2, "vector RGB565 buffer")
end

local vector_render_count = 0
local vector_font = {
  ready = true,
  error = "",
  render = function(_, _, width, height)
    vector_render_count = vector_render_count + 1
    return string.rep("\0", width * height * 2)
  end,
  stats = function()
    return { loaded = true, engine = "stb_truetype", font_bytes = 2432892,
      cache_bytes = 4096, cache_entries = 8, renders = vector_render_count }
  end,
}

local Renderer = dofile("aida_monitor/package/aida_renderer.lua")
local png40 = "\137PNG\13\10\26\10" .. string.char(0, 0, 0, 13) .. "IHDR"
  .. string.char(0, 0, 0, 40, 0, 0, 0, 40)
local png_kind, png_width, png_height = Renderer.image_info(png40)
assert(png_kind == "png" and png_width == 40 and png_height == 40, "PNG dimensions")
local png_large = "\137PNG\13\10\26\10" .. string.char(0, 0, 0, 13) .. "IHDR"
  .. string.char(0, 0, 8, 112, 0, 0, 8, 108)
local _, large_width, large_height = Renderer.image_info(png_large)
assert(large_width == 2160 and large_height == 2156, "large PNG dimensions")
local renderer = Renderer.new({ config = { history_points = 49,
  vector_font_family = "AIDA Noto Sans SC" }, layout = model, root = 1,
  vector_font = vector_font })
renderer:build()
assert(vector_render_count > 0, "vector text rendered")
renderer:apply_sample(sample)
assert(renderer.active_page == 1, "renderer first page")
assert(#renderer.views.Gph4.item.history == 1, "graph history")
renderer:apply_sample(AidaClient.parse_remote_payload("Page1{|}Simple11|OK{|}"))
assert(renderer.active_page == 2, "renderer second page")
assert(renderer:snapshot().items == 9, "renderer snapshot")
assert(renderer:snapshot().font == "AIDA Noto Sans SC", "renderer font snapshot")
assert(renderer:snapshot().font_engine == "stb_truetype", "renderer font engine")

local routes = {}
local saved_config = ""
file = {
  putcontents = function(_, body) saved_config = body return true end,
}
httpd = {
  GET = "GET",
  start = function() end,
  dynamic = function(_, route, handler) routes[route] = handler end,
  unregister = function() end,
}
local Web = dofile("aida_monitor/package/web.lua")
local web = Web.new({
  config = { host = "192.168.0.232", port = 9999,
    vector_font_family = "AIDA Noto Sans SC" },
  config_path = "/tmp/config.lua",
  route_base = "/aida_monitor",
  state = function() return {} end,
})
web:start()
local page = routes["/aida_monitor/"]()
assert(page.body:find("AIDA Noto Sans SC", 1, true), "vector font guidance")
assert(page.body:find("下载并安装同款 TTF", 1, true), "font download")
assert(page.body:find("B / I / U / S / SHADOW", 1, true), "style support")
local saved = web:save({ query = "host=192.168.0.232&port=9999&layout_path=%2F&path=%2Fsse" })
assert(saved.status == "200 OK", "web config save")
assert(saved_config:find('config.vector_font_family = "AIDA Noto Sans SC"', 1, true), "vector family persisted")
assert(saved_config:find("aida_font.so", 1, true), "vector module persisted")
assert(not saved_config:find("config.font =", 1, true), "legacy font selection removed")

print("RemoteSensor protocol tests passed")
