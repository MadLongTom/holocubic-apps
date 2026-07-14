local VectorFont = {}
VectorFont.__index = VectorFont

local function clamp(value, low, high)
  value = tonumber(value) or low
  if value < low then return low end
  if value > high then return high end
  return value
end

local function align_value(value)
  value = tostring(value or "left"):lower()
  if value == "center" then return 1 end
  if value == "right" then return 2 end
  return 0
end

local function subpixel_value(order)
  order = tostring(order or "off"):lower()
  if order == "rgb" then return 1 end
  if order == "bgr" then return 2 end
  return 0
end

local function render_options(text_style, opaque, subpixel_order)
  text_style = text_style or {}
  local font = text_style.font or {}
  local shadow = text_style.shadow or {}
  return {
    bold = font.bold == true,
    italic = font.italic == true,
    underline = text_style.underline == true,
    strike = text_style.strike == true,
    align = align_value(text_style.align),
    opaque = opaque == true,
    shadow_dx = tonumber(shadow.x) or 0,
    shadow_dy = tonumber(shadow.y) or 0,
    shadow_blur = clamp(shadow.blur or 0, 0, 2),
    shadow_color = tonumber(shadow.color) or 0,
    shadow_opacity = shadow.color and clamp(shadow.opacity or 192, 0, 255) or 0,
    subpixel = subpixel_value(subpixel_order),
  }
end

function VectorFont.new(config)
  config = config or {}
  local self = setmetatable({
    family = tostring(config.vector_font_family or "AIDA Noto Sans SC"),
    module_path = tostring(config.vector_font_module or "/sd/apps/aida_monitor/modules/aida_font.so"),
    font_path = tostring(config.vector_font_path or "/sd/apps/aida_monitor/font/aida_noto_sans_sc.ttf"),
    subpixel_order = tostring(config.font_subpixel or "rgb"):lower(),
    module = nil,
    ready = false,
    surface_ready = false,
    surfaces = {},
    error = "",
  }, VectorFont)

  local required, module_or_error = pcall(require, self.module_path)
  if not required or type(module_or_error) ~= "table" then
    self.error = "vector module unavailable: " .. tostring(module_or_error)
    return self
  end
  if type(module_or_error.open) ~= "function" or type(module_or_error.render) ~= "function" then
    self.error = "vector module API mismatch"
    return self
  end
  local opened, result, open_error = pcall(module_or_error.open, self.font_path)
  if not opened or not result then
    self.error = "vector font load failed: " .. tostring(open_error or result)
    return self
  end
  self.module = module_or_error
  self.ready = true
  self.surface_ready = type(module_or_error.surface_create) == "function"
    and type(module_or_error.surface_free) == "function"
    and type(module_or_error.surface_clear) == "function"
    and type(module_or_error.surface_copy) == "function"
    and type(module_or_error.surface_image) == "function"
    and type(module_or_error.surface_rect) == "function"
    and type(module_or_error.surface_circle) == "function"
    and type(module_or_error.surface_line) == "function"
    and type(module_or_error.surface_arc) == "function"
    and type(module_or_error.surface_text) == "function"
    and type(module_or_error.surface_pixels) == "function"
  return self
end

function VectorFont:render(text, width, height, text_style, background, chroma, opaque)
  if not self.ready or not self.module then return nil, self.error end
  text_style = text_style or {}
  local font = text_style.font or {}
  local options = render_options(text_style, opaque, self.subpixel_order)
  local ok, data, render_error = pcall(self.module.render,
    tostring(text or ""), math.floor(width), math.floor(height),
    clamp(font.size or 12, 6, 96), tonumber(text_style.color) or 0xFFFFFF,
    tonumber(background) or 0, tonumber(chroma) or 0x00FF00, options)
  if not ok or type(data) ~= "string" then
    self.error = "vector text render failed: " .. tostring(render_error or data)
    return nil, self.error
  end
  local expected = math.floor(width) * math.floor(height) * 2
  if #data ~= expected then
    self.error = "vector text buffer mismatch: " .. tostring(#data) .. "/" .. tostring(expected)
    return nil, self.error
  end
  return data
end

function VectorFont:measure(text, text_style)
  if not self.ready or not self.module or type(self.module.measure) ~= "function" then return nil end
  text_style = text_style or {}
  local font = text_style.font or {}
  local ok, width = pcall(self.module.measure, tostring(text or ""),
    clamp(font.size or 12, 6, 96), render_options(text_style, false, self.subpixel_order))
  if not ok or type(width) ~= "number" then return nil end
  return math.max(0, math.floor(width + 0.5))
end

function VectorFont:surface_create(width, height, color)
  if not self.surface_ready then return nil, "software surface API unavailable" end
  local ok, id, err = pcall(self.module.surface_create,
    math.floor(width), math.floor(height), tonumber(color) or 0)
  if not ok or type(id) ~= "number" then return nil, tostring(err or id) end
  self.surfaces[id] = { width = math.floor(width), height = math.floor(height) }
  return id
end

function VectorFont:surface_free(id)
  if not id or not self.module then return true end
  local ok, result = pcall(self.module.surface_free, id)
  self.surfaces[id] = nil
  return ok and result ~= false
end

function VectorFont:surface_clear(id, color)
  local ok, result, err = pcall(self.module.surface_clear, id, tonumber(color) or 0)
  if not ok or result == false or result == nil then return false, tostring(err or result) end
  return true
end

function VectorFont:surface_copy(destination, source)
  local ok, result, err = pcall(self.module.surface_copy, destination, source)
  if not ok or result == false or result == nil then return false, tostring(err or result) end
  return true
end

function VectorFont:surface_image(id, data, x, y, width, height, fit)
  local fit_value = ({ stretch = 0, contain = 1, cover = 2 })[tostring(fit or "stretch"):lower()] or 0
  local ok, result, err = pcall(self.module.surface_image, id, data,
    math.floor(x or 0), math.floor(y or 0), math.max(1, math.floor(width or 1)),
    math.max(1, math.floor(height or 1)), fit_value)
  if not ok or result == false or result == nil then return false, tostring(err or result) end
  return true
end

function VectorFont:surface_rect(id, x, y, width, height, color, opacity)
  local ok, result, err = pcall(self.module.surface_rect, id, math.floor(x), math.floor(y),
    math.floor(width), math.floor(height), tonumber(color) or 0, clamp(opacity or 255, 0, 255))
  if not ok or result == false or result == nil then return false, tostring(err or result) end
  return true
end

function VectorFont:surface_circle(id, cx, cy, radius, color, opacity)
  local ok, result, err = pcall(self.module.surface_circle, id,
    tonumber(cx) or 0, tonumber(cy) or 0, math.max(0, tonumber(radius) or 0),
    tonumber(color) or 0, clamp(opacity or 255, 0, 255))
  if not ok or result == false or result == nil then return false, tostring(err or result) end
  return true
end

function VectorFont:surface_line(id, x1, y1, x2, y2, color, opacity, width)
  local ok, result, err = pcall(self.module.surface_line, id,
    tonumber(x1) or 0, tonumber(y1) or 0,
    tonumber(x2) or 0, tonumber(y2) or 0,
    tonumber(color) or 0, clamp(opacity or 255, 0, 255), math.max(1, math.floor(width or 1)))
  if not ok or result == false or result == nil then return false, tostring(err or result) end
  return true
end

function VectorFont:surface_arc(id, cx, cy, radius, start_angle, end_angle, color, opacity, width)
  local ok, result, err = pcall(self.module.surface_arc, id,
    tonumber(cx) or 0, tonumber(cy) or 0, math.max(0.5, tonumber(radius) or 0.5),
    tonumber(start_angle) or 0, tonumber(end_angle) or 0,
    tonumber(color) or 0, clamp(opacity or 255, 0, 255), math.max(1, math.floor(width or 1)))
  if not ok or result == false or result == nil then return false, tostring(err or result) end
  return true
end

function VectorFont:surface_text(id, x, y, width, height, text, text_style)
  text_style = text_style or {}
  local font = text_style.font or {}
  local ok, result, err = pcall(self.module.surface_text, id,
    math.floor(x), math.floor(y), math.max(1, math.floor(width)), math.max(1, math.floor(height)),
    tostring(text or ""), clamp(font.size or 12, 6, 96),
    tonumber(text_style.color) or 0xFFFFFF,
    render_options(text_style, false, self.subpixel_order))
  if not ok or result == false or result == nil then return false, tostring(err or result) end
  return true
end

function VectorFont:surface_pixels(id)
  local meta = self.surfaces[id]
  if not meta then return nil, "surface metadata missing" end
  local ok, data, err = pcall(self.module.surface_pixels, id)
  if not ok or type(data) ~= "string" then return nil, tostring(err or data) end
  local expected = meta.width * meta.height * 2
  if #data ~= expected then return nil, "surface buffer mismatch: " .. tostring(#data) .. "/" .. tostring(expected) end
  return data
end

function VectorFont:stats()
  local base = {
    family = self.family,
    engine = self.ready and "stb_truetype" or "firmware fallback",
    loaded = self.ready,
    surface_ready = self.surface_ready,
    subpixel = self.subpixel_order,
    error = self.error,
  }
  if self.ready and self.module and type(self.module.stats) == "function" then
    local ok, stats = pcall(self.module.stats)
    if ok and type(stats) == "table" then
      for key, value in pairs(stats) do base[key] = value end
    end
  end
  return base
end

return VectorFont
