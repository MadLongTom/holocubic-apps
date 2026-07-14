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

local next_object = 10
local function object()
  next_object = next_object + 1
  return next_object
end
LV_PART_MAIN, LV_STATE_DEFAULT = 0, 0
LV_OBJ_FLAG_SCROLLABLE, LV_OBJ_FLAG_HIDDEN = 1, 2
LV_IMG_CF_TRUE_COLOR = 1
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

local Renderer = dofile("aida_monitor/package/aida_renderer.lua")
local renderer = Renderer.new({ config = { history_points = 49 }, layout = model, root = 1 })
renderer:build()
renderer:apply_sample(sample)
assert(renderer.active_page == 1, "renderer first page")
assert(#renderer.views.Gph4.item.history == 1, "graph history")
renderer:apply_sample(AidaClient.parse_remote_payload("Page1{|}Simple11|OK{|}"))
assert(renderer.active_page == 2, "renderer second page")
assert(renderer:snapshot().items == 9, "renderer snapshot")

print("RemoteSensor protocol tests passed")
