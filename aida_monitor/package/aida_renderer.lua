local Renderer = {}
Renderer.__index = Renderer

local MAIN = (rawget(_G, "LV_PART_MAIN") or 0) | (rawget(_G, "LV_STATE_DEFAULT") or 0)
local ALIGN_LEFT = rawget(_G, "LV_TEXT_ALIGN_LEFT") or 0
local ALIGN_CENTER = rawget(_G, "LV_TEXT_ALIGN_CENTER") or 1
local ALIGN_RIGHT = rawget(_G, "LV_TEXT_ALIGN_RIGHT") or 2
local FLAG_SCROLLABLE = rawget(_G, "LV_OBJ_FLAG_SCROLLABLE")
local FLAG_HIDDEN = rawget(_G, "LV_OBJ_FLAG_HIDDEN")
local GRAD_VER = rawget(_G, "LV_GRAD_DIR_VER") or 1
local CANVAS_FMT = rawget(_G, "LV_IMG_CF_TRUE_COLOR") or rawget(_G, "CANVAS_FMT_TRUE_COLOR")

local function call(fn, ...)
  if not fn then return false end
  return pcall(fn, ...)
end

local function clamp(value, low, high)
  value = tonumber(value) or low
  if value < low then return low end
  if value > high then return high end
  return value
end

local function set_hidden(object, hidden)
  if not object or not FLAG_HIDDEN then return end
  if hidden then
    call(lv_obj_add_flag, object, FLAG_HIDDEN)
  else
    call(lv_obj_clear_flag, object, FLAG_HIDDEN)
  end
end

local function make_panel(parent, x, y, w, h, color, opacity)
  local object = lv_obj_create(parent)
  call(lv_obj_set_pos, object, x or 0, y or 0)
  call(lv_obj_set_size, object, math.max(1, w or 1), math.max(1, h or 1))
  call(lv_obj_set_style_bg_color, object, color or 0, MAIN)
  call(lv_obj_set_style_bg_opa, object, opacity == nil and 255 or opacity, MAIN)
  call(lv_obj_set_style_border_width, object, 0, MAIN)
  call(lv_obj_set_style_radius, object, 0, MAIN)
  call(lv_obj_set_style_pad_all, object, 0, MAIN)
  if FLAG_SCROLLABLE then call(lv_obj_clear_flag, object, FLAG_SCROLLABLE) end
  return object
end

local function apply_gradient(object, colors)
  if not object or not colors then return end
  call(lv_obj_set_style_bg_color, object, colors[1] or 0, MAIN)
  if colors[2] and colors[2] ~= colors[1] then
    call(lv_obj_set_style_bg_grad_color, object, colors[2], MAIN)
    call(lv_obj_set_style_bg_grad_dir, object, GRAD_VER, MAIN)
    call(lv_obj_set_style_bg_main_stop, object, 0, MAIN)
    call(lv_obj_set_style_bg_grad_stop, object, 255, MAIN)
  end
end

local function style_align(value)
  value = tostring(value or "left"):lower()
  if value == "right" then return ALIGN_RIGHT end
  if value == "center" then return ALIGN_CENTER end
  return ALIGN_LEFT
end

local function make_label(parent, geometry, text_style, width)
  local object = lv_label_create(parent)
  local x = geometry and geometry.x or 0
  local y = geometry and geometry.y or 0
  local w = width or (geometry and geometry.w) or 0
  if w <= 0 then w = 320 - x end
  call(lv_obj_set_pos, object, x, y)
  call(lv_obj_set_width, object, math.max(1, w))
  call(lv_label_set_text, object, tostring(text_style and text_style.text or ""))
  call(lv_obj_set_style_text_color, object, text_style and text_style.color or 0xFFFFFF, MAIN)
  call(lv_obj_set_style_text_opa, object, 255, MAIN)
  call(lv_obj_set_style_text_font, object, text_style and text_style.font and text_style.font.size or 12, MAIN)
  call(lv_obj_set_style_text_align, object, style_align(text_style and text_style.align), MAIN)
  return object
end

local function canvas_create(parent, width, height)
  if not lv_canvas_create then return nil end
  if CANVAS_FMT then
    local ok, object = pcall(lv_canvas_create, parent, width, height, CANVAS_FMT)
    if ok then return object end
  end
  local ok, object = pcall(lv_canvas_create, parent, width, height)
  return ok and object or nil
end

local function canvas_begin(canvas)
  if lv_canvas_frame_begin then return call(lv_canvas_frame_begin, canvas) end
  if lv_canvas_begin then return call(lv_canvas_begin, canvas) end
  return false
end

local function canvas_end(canvas, explicit)
  if not explicit then return end
  if lv_canvas_frame_end then call(lv_canvas_frame_end, canvas)
  elseif lv_canvas_end then call(lv_canvas_end, canvas) end
end

local function fill(canvas, color)
  if lv_canvas_fill_bg then call(lv_canvas_fill_bg, canvas, color, 255)
  elseif lv_canvas_fill then call(lv_canvas_fill, canvas, color, 255) end
end

local function draw_rect(canvas, x, y, w, h, color, opacity)
  if w <= 0 or h <= 0 then return end
  local ok = call(lv_canvas_draw_rect, canvas, math.floor(x), math.floor(y), math.floor(w), math.floor(h), color, opacity or 255)
  if not ok then
    call(lv_canvas_draw_rect, canvas, math.floor(x), math.floor(y), math.floor(w), math.floor(h), {
      bg_color = color, bg_opa = opacity or 255, border_width = 0, radius = 0,
    })
  end
end

local function draw_line(canvas, x1, y1, x2, y2, color, opacity, width)
  call(lv_canvas_draw_line, canvas, math.floor(x1 + 0.5), math.floor(y1 + 0.5),
    math.floor(x2 + 0.5), math.floor(y2 + 0.5), color, opacity or 255, width or 1)
end

local function draw_text(canvas, x, y, width, text, color, size, align, opacity)
  local ok = call(lv_canvas_draw_text, canvas, math.floor(x), math.floor(y), math.max(1, math.floor(width)),
    tostring(text or ""), color or 0xFFFFFF, opacity or 255, align or ALIGN_LEFT, size or 10)
  if not ok then
    call(lv_canvas_draw_text, canvas, math.floor(x), math.floor(y), math.max(1, math.floor(width)),
      tostring(text or ""), { color = color or 0xFFFFFF, opa = opacity or 255,
      align = align or ALIGN_LEFT, font_size = size or 10 })
  end
end

local function graph_range(item)
  local p = item.params or {}
  local minimum = tonumber(p.min_value) or 0
  local maximum = tonumber(p.max_value) or 100
  if p.autoscale and #item.history > 0 then
    minimum, maximum = item.history[1], item.history[1]
    for i = 2, #item.history do
      minimum = math.min(minimum, item.history[i])
      maximum = math.max(maximum, item.history[i])
    end
    if p.base_100 then
      minimum = math.floor(minimum * 0.009 + 0.5) * 100
      maximum = math.floor(maximum * 0.011 + 0.5) * 100
    else
      minimum = math.floor(minimum * 0.9 + 0.5)
      maximum = math.floor(maximum * 1.1 + 0.5)
    end
  end
  if maximum <= minimum then
    if minimum == 0 then maximum = 1 else maximum = minimum + math.abs(minimum * 0.1) end
  end
  return minimum, maximum
end

local function render_graph(view)
  local item, canvas = view.item, view.object
  if not canvas then return end
  local p = item.params or {}
  local width, height = item.geometry.w, item.geometry.h
  local explicit = canvas_begin(canvas)
  fill(canvas, p.show_background and p.background or item.canvas_background or 0x000000)

  local left, top, right, bottom = 0, 0, width - 1, height - 1
  if p.show_frame then left, top, right, bottom = 1, 1, width - 2, height - 2 end
  local scale_width = p.show_scale and math.min(28, math.max(18, (p.font_size or 8) * 3)) or 0
  if p.show_scale then
    if p.right_align then right = right - scale_width else left = left + scale_width end
  end
  local plot_w, plot_h = math.max(1, right - left), math.max(1, bottom - top)
  local minimum, maximum = graph_range(item)

  if p.show_grid then
    local density = math.max(2, tonumber(p.grid_density) or 10)
    local offset = tonumber(item.grid_offset) or 0
    local x = left + (offset % density)
    while x <= right do
      draw_line(canvas, x, top, x, bottom, p.grid_color or 0x333333, 255, 1)
      x = x + density
    end
    local y = top
    while y <= bottom do
      draw_line(canvas, left, y, right, y, p.grid_color or 0x333333, 255, 1)
      y = y + density
    end
  end

  local history = item.history
  local count = #history
  local step = math.max(1, tonumber(p.step) or 1)
  local function point(i)
    local x = right - (count - i) * step
    local ratio = clamp((history[i] - minimum) / (maximum - minimum), 0, 1)
    local y = bottom - ratio * plot_h
    return x, y
  end

  if p.graph_type == "HG" then
    for i = 1, count do
      local x, y = point(i)
      if x >= left then draw_rect(canvas, x, y, math.max(1, step - 1), bottom - y + 1, p.graph_color or 0xFFFFFF, 255) end
    end
  else
    for i = 2, count do
      local x1, y1 = point(i - 1)
      local x2, y2 = point(i)
      if x2 >= left then
        if p.graph_type == "AG" then
          local start_x = math.floor(math.max(left, x1))
          local end_x = math.floor(math.max(left, x2))
          local span = math.max(1, x2 - x1)
          for x = start_x, end_x do
            local ratio = clamp((x - x1) / span, 0, 1)
            local y = y1 + (y2 - y1) * ratio
            draw_line(canvas, x, y, x, bottom, p.graph_color or 0xFFFFFF, 84, 1)
          end
        end
        draw_line(canvas, math.max(left, x1), y1, x2, y2, p.graph_color or 0xFFFFFF, 255, p.thick or 1)
      end
    end
  end

  if p.show_scale then
    local text_x = p.right_align and (right + 2) or 0
    local align = p.right_align and ALIGN_LEFT or ALIGN_RIGHT
    draw_text(canvas, text_x, top, scale_width - 2, tostring(math.floor(maximum + 0.5)),
      p.font_color, p.font_size, align, 255)
    draw_text(canvas, text_x, math.max(top, bottom - (p.font_size or 8) - 1), scale_width - 2,
      tostring(math.floor(minimum + 0.5)), p.font_color, p.font_size, align, 255)
  end
  if p.show_frame then
    draw_line(canvas, 0, 0, width - 1, 0, p.frame_color, 255, 1)
    draw_line(canvas, width - 1, 0, width - 1, height - 1, p.frame_color, 255, 1)
    draw_line(canvas, width - 1, height - 1, 0, height - 1, p.frame_color, 255, 1)
    draw_line(canvas, 0, height - 1, 0, 0, p.frame_color, 255, 1)
  end
  canvas_end(canvas, explicit)
end

local function arc_span(canvas, cx, cy, radius, start_angle, span, color, width)
  if span <= 0 then return end
  if span >= 359.5 then
    call(lv_canvas_draw_arc, canvas, cx, cy, radius, 0, 359, color, 255, width)
    return
  end
  local first = start_angle % 360
  if first < 0 then first = first + 360 end
  local last = first + span
  if last <= 360 then
    call(lv_canvas_draw_arc, canvas, cx, cy, radius, math.floor(first), math.floor(last), color, 255, width)
  else
    call(lv_canvas_draw_arc, canvas, cx, cy, radius, math.floor(first), 359, color, 255, width)
    call(lv_canvas_draw_arc, canvas, cx, cy, radius, 0, math.floor(last - 360), color, 255, width)
  end
end

local function render_arc(view)
  local item, canvas = view.item, view.object
  if not canvas then return end
  local p = item.params or {}
  local width, height = item.geometry.w, item.geometry.h
  local radius = math.max(1, math.floor(math.min(width, height) / 2) - 1)
  local thickness = clamp(p.thickness or 4, 1, radius)
  local cx, cy = math.floor(width / 2), math.floor(height / 2)
  local explicit = canvas_begin(canvas)
  fill(canvas, item.canvas_background or 0x000000)
  if p.fill and radius > thickness then
    local inner_radius = math.max(1, radius - thickness)
    arc_span(canvas, cx, cy, math.floor(inner_radius / 2), 0, 359.5,
      p.fill_color or item.canvas_background or 0x000000, inner_radius)
  end
  arc_span(canvas, cx, cy, radius - math.floor(thickness / 2), 0, 359.5,
    item.background_color or 0x202020, thickness)
  arc_span(canvas, cx, cy, radius - math.floor(thickness / 2), p.start_angle or 0,
    clamp(item.percent or 0, 0, 100) * 3.6, item.active_color or 0x00FF00, thickness)
  if p.show_text then
    local size = p.font_size or 10
    draw_text(canvas, 0, math.floor((height - size) / 2), width, item.display_text or "",
      p.font_color or 0xFFFFFF, size, ALIGN_CENTER, 255)
  end
  canvas_end(canvas, explicit)
end

local function safe_filename(index, src)
  local name = tostring(src or ""):gsub("[?#].*$", ""):match("([^/\\]+)$") or ("image" .. index .. ".bin")
  name = name:gsub("[^%w%._%-]", "_")
  if name == "" then name = "image" .. index .. ".bin" end
  return tostring(index) .. "_" .. name
end

local function create_image_object(parent, path)
  local is_gif = path:lower():match("%.gif$") ~= nil
  if is_gif and lv_gif_create and lv_gif_set_src then
    local object = lv_gif_create(parent)
    call(lv_gif_set_src, object, path)
    return object
  end
  if lv_img_create and lv_img_set_src then
    local object = lv_img_create(parent)
    call(lv_img_set_src, object, path)
    return object
  end
  return nil
end

function Renderer.new(opts)
  local self = setmetatable({}, Renderer)
  self.config = opts.config or {}
  self.layout = opts.layout
  self.root = opts.root or lv_scr_act()
  self.resource_url = opts.resource_url
  self.log = opts.log or function() end
  self.pages = {}
  self.views = {}
  self.image_queue = {}
  self.image_busy = false
  self.active_page = 1
  return self
end

function Renderer:make_text(page, item, geometry, text_style, width)
  local object = make_label(page, geometry, text_style, width)
  return { object = object, item = item, kind = "text" }
end

function Renderer:build_sensor(page, item)
  local g = item.geometry
  local view = { item = item, kind = "sensor" }
  local width = g.w > 0 and g.w or math.max(1, 320 - g.x)
  if item.label then
    local sg = item.label.style or {}
    view.label = make_label(page, { x = g.x, y = g.y }, item.label.text_style, width)
  end
  if item.value then
    local vg = item.value.style or {}
    local x = g.x + (tonumber((vg.left or ""):match("([%-]?%d+)")) or 0)
    view.value = make_label(page, { x = x, y = g.y }, item.value.text_style, width - (x - g.x))
  end
  if item.unit then
    local ug = item.unit.style or {}
    local unit_style = item.unit.text_style
    unit_style.align = "right"
    view.unit = make_label(page, { x = g.x, y = g.y }, unit_style, width)
  end
  if item.bar then
    local bg = item.bar.geometry
    local bar_x = g.x + bg.x
    local bar_y = g.y + bg.y + (item.bar.margin_top or 0)
    local bar_w = bg.w > 0 and bg.w or width
    local bar_h = bg.h > 0 and bg.h or 4
    view.bar_bg = make_panel(page, bar_x, bar_y, bar_w, bar_h, item.bar.background[1], 255)
    apply_gradient(view.bar_bg, item.bar.background)
    view.bar_fg = make_panel(view.bar_bg, 0, 0, math.max(1, bar_w * (item.bar.percent or 0) / 100), bar_h,
      item.bar.foreground[1], 255)
    apply_gradient(view.bar_fg, item.bar.foreground)
    view.bar_width = bar_w
  end
  return view
end

function Renderer:build_item(page, item)
  local view
  if item.kind == "label" or item.kind == "simple" then
    view = self:make_text(page, item, item.geometry, item.text_style)
  elseif item.kind == "sensor" then
    view = self:build_sensor(page, item)
  elseif item.kind == "graph" or item.kind == "arc" then
    item.canvas_background = self.layout.background or 0
    local canvas = canvas_create(page, math.max(1, item.geometry.w), math.max(1, item.geometry.h))
    if canvas then call(lv_obj_set_pos, canvas, item.geometry.x, item.geometry.y) end
    view = { object = canvas, item = item, kind = item.kind }
    if item.kind == "graph" then render_graph(view) else render_arc(view) end
  elseif item.kind == "image" then
    view = { item = item, kind = "image", object = nil }
    self.image_queue[#self.image_queue + 1] = { page = page, item = item, view = view }
  end
  if view then
    self.views[item.id] = view
    if item.value_update then self.views[item.value_update] = view end
    if item.bar and item.bar.update_id then self.views[item.bar.update_id] = view end
    if item.update_id then self.views[item.update_id] = view end
  end
end

function Renderer:build()
  call(lv_obj_clean, self.root)
  call(lv_obj_set_style_bg_color, self.root, self.layout.background or 0, MAIN)
  call(lv_obj_set_style_bg_opa, self.root, 255, MAIN)
  if FLAG_SCROLLABLE then call(lv_obj_clear_flag, self.root, FLAG_SCROLLABLE) end
  for index = 1, self.layout.page_count do
    local page = make_panel(self.root, 0, 0, 320, 240, self.layout.background or 0, 255)
    self.pages[index] = page
    set_hidden(page, index ~= self.active_page)
    for _, item in ipairs(self.layout.pages[index].items) do self:build_item(page, item) end
  end
  self:load_next_image()
end

function Renderer:load_next_image()
  if self.image_busy or #self.image_queue == 0 then return end
  local pending = table.remove(self.image_queue, 1)
  local cache_dir = self.config.cache_dir or "/sd/apps/aida_monitor/cache"
  if file and file.mkdir then call(file.mkdir, cache_dir) end
  local path = cache_dir .. "/" .. safe_filename(pending.item.id:match("%d+") or 1, pending.item.src)
  local function attach()
    local object = create_image_object(pending.page, path)
    pending.view.object = object
    if object then call(lv_obj_set_pos, object, pending.item.geometry.x, pending.item.geometry.y) end
  end
  if not http or not http.get or not self.resource_url then
    if file and file.exists then
      local ok, exists = pcall(file.exists, path)
      if ok and exists then attach() end
    end
    self:load_next_image()
    return
  end
  self.image_busy = true
  local headers = "Accept: image/*\r\nAccept-Encoding: identity\r\nCache-Control: no-cache\r\n\r\n"
  local ok = pcall(function()
    http.get(self.resource_url(pending.item.src), headers, function(code, body)
      self.image_busy = false
      if tonumber(code) == 200 and type(body) == "string" and #body > 0 and file and file.putcontents then
        local saved, result = pcall(file.putcontents, path, body)
        if saved and result ~= false then attach() else self.log("image_save_error", path) end
      else
        self.log("image_http_error", pending.item.src, code)
      end
      self:load_next_image()
    end)
  end)
  if not ok then
    self.image_busy = false
    self:load_next_image()
  end
end

function Renderer:set_page(index)
  index = clamp(index, 1, #self.pages)
  if index == self.active_page then return end
  for i, page in ipairs(self.pages) do set_hidden(page, i ~= index) end
  self.active_page = index
end

function Renderer:apply_update(update)
  local view = self.views[update.id]
  if not view then return false end
  if update.kind == "text" then
    if view.kind == "sensor" and view.value then call(lv_label_set_text, view.value, tostring(update.text or ""))
    elseif view.object then call(lv_label_set_text, view.object, tostring(update.text or "")) end
  elseif update.kind == "bar" and view.bar_fg then
    local width = math.max(1, math.floor(view.bar_width * clamp(update.percent, 0, 100) / 100 + 0.5))
    call(lv_obj_set_width, view.bar_fg, width)
    if update.background then apply_gradient(view.bar_bg, update.background) end
    if update.foreground then apply_gradient(view.bar_fg, update.foreground) end
  elseif update.kind == "graph" then
    local history = view.item.history
    history[#history + 1] = tonumber(update.value) or 0
    local max_points = view.item.max_points or self.config.history_points or 49
    while #history > max_points do table.remove(history, 1) end
    view.item.grid_offset = (tonumber(view.item.grid_offset) or 0) - (view.item.params and view.item.params.step or 1)
    render_graph(view)
  elseif update.kind == "arc" then
    view.item.percent = tonumber(update.percent) or 0
    view.item.display_text = update.text or ""
    view.item.background_color = update.background_color
    view.item.active_color = update.active_color
    render_arc(view)
  end
  return true
end

function Renderer:apply_sample(sample)
  if sample.page then self:set_page(sample.page) end
  for _, update in ipairs(sample.updates or {}) do self:apply_update(update) end
end

function Renderer:snapshot()
  return {
    page = self.active_page,
    pages = #self.pages,
    items = self.layout.item_count or 0,
    counts = self.layout.counts or {},
  }
end

function Renderer:destroy()
  self.image_queue = {}
  self.image_busy = false
  self.pages = {}
  self.views = {}
end

return Renderer
