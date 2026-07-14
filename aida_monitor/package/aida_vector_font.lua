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

function VectorFont.new(config)
  config = config or {}
  local self = setmetatable({
    family = tostring(config.vector_font_family or "AIDA Noto Sans SC"),
    module_path = tostring(config.vector_font_module or "/sd/apps/aida_monitor/modules/aida_font.so"),
    font_path = tostring(config.vector_font_path or "/sd/apps/aida_monitor/font/aida_noto_sans_sc.ttf"),
    module = nil,
    ready = false,
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
  return self
end

function VectorFont:render(text, width, height, text_style, background, chroma, opaque)
  if not self.ready or not self.module then return nil, self.error end
  text_style = text_style or {}
  local font = text_style.font or {}
  local shadow = text_style.shadow or {}
  local options = {
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
  }
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

function VectorFont:stats()
  local base = {
    family = self.family,
    engine = self.ready and "stb_truetype" or "firmware fallback",
    loaded = self.ready,
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
