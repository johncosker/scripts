-- A GUI front-end for creating designs
--@ module = false

-- TODOS ====================

-- Must Haves
-----------------------------
-- Better UI, it's starting to get really crowded
-- Right click when dragging center seems off
-- Freeform shape seems to slow stuff, check needs_update?

-- Should Haves
-----------------------------
-- Refactor duplicated code into functions
--  File is getting long... might be time to consider creating additional modules
-- All the various states are getting hard to keep track of, e.g. placing extra/mirror/mark/etc...
--   Should consolidate the states into a single state attribute with enum values
-- Keyboard support
-- As the number of shapes and designations grow it might be better to have list menus for them instead of cycle
-- Grid view without slowness (can ignore if next TODO is done, since nrmal mining mode has grid view)
--   Lags when drawing the full screen grid on each frame render
-- Integrate with default mining mode for designation type, priority, etc... (possible?)
-- Figure out how to remove dug stairs with mode (nothing seems to work, include 'dig ramp')
-- 'No overwrite' mode to not overwrite existing designations
-- Snap to grid, or angle, like 45 degrees, or some kind of tools to assist with symmetrical designs

-- Nice To Haves
-----------------------------
-- Exploration pattern ladder https://dwarffortresswiki.org/index.php/DF2014:Exploratory_mining#Ladder_Rows

-- Stretch Goals
-----------------------------
-- Shape preview in panel
-- Shape designer in preview panel to draw repeatable shapes i'e' 2x3 room with door
-- 3D shapes, would allow stuff like spiral staircases/minecart tracks and other neat stuff, probably not too hard

-- END TODOS ================

local gui = require("gui")
local guidm = require("gui.dwarfmode")
local widgets = require("gui.widgets")
local quickfort = reqscript("quickfort")
local shapes = reqscript("internal/design/shapes")
local utilities = reqscript("internal/design/utilities")
local interface = reqscript("internal/design/interface")

local tile_attrs = df.tiletype.attrs
local Point = utilities.Point
local Points = utilities.Points
local PenCache = utilities.PenCache
local to_pen = dfhack.pen.parse

local guide_tile_pen = to_pen {
    ch = "+",
    fg = COLOR_YELLOW,
    tile = dfhack.screen.findGraphicsTile(
        "CURSORS",
        0,
        22
    ),
}

local mirror_guide_pen = to_pen {
    ch = "+",
    fg = COLOR_YELLOW,
    tile = dfhack.screen.findGraphicsTile(
        "CURSORS",
        1,
        22
    ),
}

---
--- HelpWindow
---

DESIGN_HELP_DEFAULT = {
    "gui/design Help",
    "===============",
    NEWLINE,
    "This is a default help text."
}

CONSTRUCTION_HELP = {
    "gui/design Help: Building Filters",
    "=================================",
    NEWLINE,
    "Adding material filters to this tool is planned but not implemented at this time.",
    NEWLINE,
    "Use `buildingplan` to configure filters for the desired construction types. This tool will use the current buildingplan filters for an building type."
}

HelpWindow = defclass(HelpWindow, widgets.Window)
HelpWindow.ATTRS {
    frame_title = 'gui/design Help',
    frame = { w = 43, h = 20, t = 10, l = 10 },
    resizable = true,
    resize_min = { w = 43, h = 20 },
    message = DESIGN_HELP_DEFAULT
}

function HelpWindow:init()
    self:addviews {
        widgets.ResizingPanel { autoarrange_subviews = true,
            frame = { t = 0, l = 0 },
            subviews = {
                widgets.WrappedLabel {
                    view_id = 'help_text',
                    frame = { t = 0, l = 0 },
                    text_to_wrap = function() return self.message end,
                }
            }
        }
    }
end

local function get_icon_pens()
    local start = dfhack.textures.getControlPanelTexposStart()
    local valid = start > 0
    start = start + 10

    local enabled_pen_left = dfhack.pen.parse { fg = COLOR_CYAN,
        tile = valid and (start + 0) or nil, ch = string.byte('[') }
    local enabled_pen_center = dfhack.pen.parse { fg = COLOR_LIGHTGREEN,
        tile = valid and (start + 1) or nil, ch = 251 } -- check
    local enabled_pen_right = dfhack.pen.parse { fg = COLOR_CYAN,
        tile = valid and (start + 2) or nil, ch = string.byte(']') }
    local disabled_pen_left = dfhack.pen.parse { fg = COLOR_CYAN,
        tile = valid and (start + 3) or nil, ch = string.byte('[') }
    local disabled_pen_center = dfhack.pen.parse { fg = COLOR_RED,
        tile = valid and (start + 4) or nil, ch = string.byte('x') }
    local disabled_pen_right = dfhack.pen.parse { fg = COLOR_CYAN,
        tile = valid and (start + 5) or nil, ch = string.byte(']') }
    local button_pen_left = dfhack.pen.parse { fg = COLOR_CYAN,
        tile = valid and (start + 6) or nil, ch = string.byte('[') }
    local button_pen_right = dfhack.pen.parse { fg = COLOR_CYAN,
        tile = valid and (start + 7) or nil, ch = string.byte(']') }
    local help_pen_center = dfhack.pen.parse {
        tile = valid and (start + 8) or nil, ch = string.byte('?')
    }
    local configure_pen_center = dfhack.pen.parse {
        tile = valid and (start + 9) or nil, ch = 15
    } -- gear/masterwork symbol
    return enabled_pen_left, enabled_pen_center, enabled_pen_right,
        disabled_pen_left, disabled_pen_center, disabled_pen_right,
        button_pen_left, button_pen_right,
        help_pen_center, configure_pen_center
end

local ENABLED_PEN_LEFT, ENABLED_PEN_CENTER, ENABLED_PEN_RIGHT,
DISABLED_PEN_LEFT, DISABLED_PEN_CENTER, DISABLED_PEN_RIGHT,
BUTTON_PEN_LEFT, BUTTON_PEN_RIGHT,
HELP_PEN_CENTER, CONFIGURE_PEN_CENTER = get_icon_pens()

local uibs = df.global.buildreq

local function get_cur_filters()
    return dfhack.buildings.getFiltersByType({}, uibs.building_type,
        uibs.building_subtype, uibs.custom_type)
end

-- Debug window

SHOW_DEBUG_WINDOW = true

local function table_to_string(tbl, indent)
    indent = indent or ""
    local result = {}
    for k, v in pairs(tbl) do
        local key = type(k) == "number" and "[" .. tostring(k) .. "]" or tostring(k)
        if type(v) == "table" then
            table.insert(result, indent .. key .. " = {")
            local subTable = table_to_string(v, indent .. "  ")
            for _, line in ipairs(subTable) do
                table.insert(result, line)
            end
            table.insert(result, indent .. "},")
        elseif type(v) == "function" then
            local res = v()
            local value = type(res) == "number" and tostring(res) or "\"" .. tostring(res) .. "\""
            table.insert(result, indent .. key .. " = " .. value .. ",")
        else
            local value = type(v) == "number" and tostring(v) or "\"" .. tostring(v) .. "\""
            table.insert(result, indent .. key .. " = " .. value .. ",")
        end
    end
    return result
end

DesignDebugWindow = defclass(DesignDebugWindow, widgets.Window)
DesignDebugWindow.ATTRS {
    frame_title = "Debug",
    frame = {
        w = 47,
        h = 40,
        l = 10,
        t = 8,
    },
    resizable = true,
    resize_min = { h = 30 },
    autoarrange_subviews = true,
    autoarrange_gap = 1,
    design_window = DEFAULT_NIL
}

function DesignDebugWindow:init()

    local attrs = {
        -- "shape", -- prints a lot of lines due to the self.arr, best to disable unless needed, TODO add a 'get debug string' function
        "prio",
        "autocommit",
        "cur_shape",
        "placing_extra",
        "placing_mark",
        "prev_center",
        "start_center",
        "extra_points",
        "last_mouse_point",
        "needs_update",
        "#marks",
        "placing_mirror",
        "mirror_point",
        "mirror",
        "show_guides"
    }

    if not self.design_window then
        return
    end

    for i, a in pairs(attrs) do
        local attr = a
        local sizeOnly = string.sub(attr, 1, 1) == "#"

        if (sizeOnly) then
            attr = string.sub(attr, 2)
        end

        self:addviews { widgets.WrappedLabel {
            view_id = "debug_label_" .. attr,
            text_to_wrap = function()
                if type(self.design_window[attr]) ~= "table" then
                    return tostring(attr) .. ": " .. tostring(self.design_window[attr])
                end

                if sizeOnly then
                    return '#' .. tostring(attr) .. ": " .. tostring(#self.design_window[attr])
                else
                    return { tostring(attr) .. ": ", table.unpack(table_to_string(self.design_window[attr], "  ")) }
                end
            end,
        } }
    end
end

--
-- Design
--

Design = defclass(Design, widgets.Window)
Design.ATTRS {
    name = "design_window",
    frame_title = "Design",
    frame = {
        w = 40,
        h = 45,
        r = 2,
        t = 18,
    },
    resizable = true,
    resize_min = { h = 30 },
    autoarrange_subviews = true,
    autoarrange_gap = 1,
    shape = DEFAULT_NIL,
    prio = 4,
    autocommit = true,
    cur_shape = 1,
    placing_extra = { active = false, index = nil },
    placing_mark = { active = true, index = 1, continue = true },
    prev_center = DEFAULT_NIL,
    start_center = DEFAULT_NIL,
    extra_points = Points {},
    last_mouse_point = DEFAULT_NIL,
    needs_update = false,
    marks = Points {},
    placing_mirror = false,
    mirror_point = DEFAULT_NIL,
    mirror = { horizontal = false, vertical = false },
    show_guides = true
}

function Design:init()
    self:addviews {
        interface.ActionPanel {
            view_id = "action_panel",
            design_panel = self,
            get_extra_pt_count = function()
                return #self.extra_points
            end,
        },
        interface.MarksPanel {
            view_id = "marks_panel",
            design_panel = self,
        },
        interface.GenericOptionsPanel {
            view_id = "generic_panel",
            design_panel = self,
        }
    }

    self.pen_cache = PenCache {
        is_drag_pt_fn = function(point)
            local drag_point = false

            -- Basic shapes are bounded by rectangles and therefore can have corner drag points
            -- even if they're not real points in the shape
            if #self.marks >= self.shape.min_points and self.shape.basic_shape then
                local shape_top_left, shape_bot_right = self.shape:get_point_dims()
                local shape_top_right = Point { x = shape_bot_right.x, y = shape_top_left.y }
                local shape_bot_left = Point { x = shape_top_left.x, y = shape_bot_right.y }
                if point == shape_top_left and self.shape.drag_corners.nw then drag_point = true
                elseif point == shape_top_right and self.shape.drag_corners.ne then drag_point = true
                elseif point == shape_bot_left and self.shape.drag_corners.sw then drag_point = true
                elseif point == shape_bot_right and self.shape.drag_corners.se then drag_point = true
                end
            end

            for _, mark in ipairs(self.marks) do
                if mark == point then
                    drag_point = true
                end
            end

            if self.mirror_point and self.mirror_point == point then
                drag_point = true
            end

            return drag_point
        end,
        is_extra_pt_fn = function(point)
            -- Is there an extra point
            local is_extra_point = false
            for _, extra_point in ipairs(self.extra_points) do
                if point == extra_point then
                    is_extra_point = true
                    break
                end
            end

            -- Show center point if both marks are set
            if (self.shape.basic_shape and #self.marks == self.shape.max_points) or
                (not self.shape.basic_shape and not self.placing_mark.active and #self.marks > 0) then
                local center = self.shape:get_center()

                if point == center then
                    is_extra_point = true
                end
            end

            return is_extra_point
        end,

        get_arr_fn = function() if self.shape then return self.shape.arr else return {} end end,
    }
end

function Design:postinit()
    -- Check to see if we're moving a point, or some change was made that implise we need to update the shape
    -- This stop us needing to update the shape geometery every frame which can tank FPS
    function Design:shape_needs_update()
        -- if #self.marks < self.shape.min_points then return false end

        if self.needs_update then return true end

        local mouse_pos = dfhack.gui.getMousePos()
        if mouse_pos then
            local mouse_moved = (not self.last_mouse_point and mouse_pos) or (self.last_mouse_point ~= Point(mouse_pos))

            if self.placing_mark.active and mouse_moved then
                return true
            end

            if self.placing_extra.active and mouse_moved then
                return true
            end
        end

        return false
    end

    self.shape = shapes.all_shapes[self.subviews.shape_name:getOptionValue()]
    if self.shape then
        self:add_shape_options()
    end
end

-- Add shape specific options dynamically based on the shape.options table
-- Currently only supports 'bool' aka toggle and 'plusminus' which creates
-- a pair of HotKeyLabel's to increment/decrement a value
-- Will need to update as needed to add more option types
function Design:add_shape_options()
    local prefix = "shape_option_"
    for i, view in ipairs(self.subviews or {}) do
        if view.view_id:sub(1, #prefix) == prefix then
            self.subviews[i] = nil
        end
    end

    if not self.shape or not self.shape.options then return end

    self:addviews {
        widgets.WrappedLabel {
            view_id = "shape_option_label",
            text_to_wrap = "Shape Settings:\n",
        }
    }

    for key, option in pairs(self.shape.options) do
        if option.type == "bool" then
            self:addviews {
                widgets.ToggleHotkeyLabel {
                    view_id = "shape_option_" .. option.name,
                    key = option.key,
                    label = option.name,
                    active = true,
                    enabled = function()
                        if not option.enabled then
                            return true
                        else
                            return self.shape.options[option.enabled[1]].value == option.enabled[2]
                        end
                    end,
                    disabled = false,
                    show_tooltip = true,
                    initial_option = option.value,
                    on_change = function(new, old)
                        self.shape.options[key].value = new
                        self.needs_update = true
                    end,
                }
            }

        elseif option.type == "plusminus" then
            local min, max = nil, nil
            if type(option['min']) == "number" then
                min = option['min']
            elseif type(option['min']) == "function" then
                min = option['min'](self.shape)
            end
            if type(option['max']) == "number" then
                max = option['max']
            elseif type(option['max']) == "function" then
                max = option['max'](self.shape)
            end

            self:addviews {
                widgets.HotkeyLabel {
                    view_id = "shape_option_" .. option.name .. "_minus",
                    key = option.keys[1],
                    label = "Decrease " .. option.name,
                    active = true,
                    enabled = function()
                        if option.enabled then
                            if self.shape.options[option.enabled[1]].value ~= option.enabled[2] then
                                return false
                            end
                        end
                        return not min or
                            (self.shape.options[key].value > min)
                    end,
                    disabled = false,
                    show_tooltip = true,
                    on_activate = function()
                        self.shape.options[key].value =
                        self.shape.options[key].value - 1
                        self.needs_update = true
                    end,
                },
                widgets.HotkeyLabel {
                    view_id = "shape_option_" .. option.name .. "_plus",
                    key = option.keys[2],
                    label = "Increase " .. option.name,
                    active = true,
                    enabled = function()
                        if option.enabled then
                            if self.shape.options[option.enabled[1]].value ~= option.enabled[2] then
                                return false
                            end
                        end
                        return not max or
                            (self.shape.options[key].value <= max)
                    end,
                    disabled = false,
                    show_tooltip = true,
                    on_activate = function()
                        self.shape.options[key].value =
                        self.shape.options[key].value + 1
                        self.needs_update = true
                    end,
                }
            }
        end
    end
end

function Design:on_transform(val)
    local center = self.shape:get_center() -- jcoskerTODO

    -- Save mirrored points first
    if self.mirror_point then
        self.marks = self:get_mirrored_points(self.marks)
        self.mirror_point = nil
    end

    -- Transform marks jcoskerTODO
    for i, mark in ipairs(self.marks) do
        -- mark = self.marks[i]
        local x, y = mark.x, mark.y
        if val == 'cw' then
            x, y = center.x - (y - center.y), center.y + (x - center.x)
        elseif val == 'ccw' then
            x, y = center.x + (y - center.y), center.y - (x - center.x)
        elseif val == 'fliph' then
            x = center.x - (x - center.x)
        elseif val == 'flipv' then
            y = center.y - (y - center.y)
        end
        self.marks[i] = Point { x = math.floor(x + 0.5), y = math.floor(y + 0.5), z = self.marks[i].z }
    end

    -- Transform extra points
    for i, point in ipairs(self.extra_points) do
        -- point = self.extra_points[i]
        local x, y = point.x, point.y
        if val == 'cw' then
            x, y = center.x - (y - center.y), center.y + (x - center.x)
        elseif val == 'ccw' then
            x, y = center.x + (y - center.y), center.y - (x - center.x)
        elseif val == 'fliph' then
            x = center.x - (x - center.x)
        elseif val == 'flipv' then
            y = center.y - (y - center.y)
        end
        self.extra_points[i] = Point { x = math.floor(x + 0.5), y = math.floor(y + 0.5), z = self.extra_points[i].z }
    end

    -- Calculate center point after transformation
    self.shape:update(self.marks, self.extra_points)
    local new_center = self.shape:get_center()

    local delta = { x = center.x - new_center.x, y = center.y - new_center.y } --jcoskerTODO
    self.marks:transform(delta)
    self.extra_points:transform(delta)

    self:updateLayout()
    self.needs_update = true
end

function Design:get_view_bounds()
    if #self.marks == 0 then return nil end

    local min_x = self.marks[1].x
    local max_x = self.marks[1].x
    local min_y = self.marks[1].y
    local max_y = self.marks[1].y
    local min_z = self.marks[1].z
    local max_z = self.marks[1].z

    local marks_plus_next = Points {}
    local p = self.marks:copy()
    marks_plus_next = self.marks:copy() -- jcoskerTODO
    local mouse_pos = dfhack.gui.getMousePos()
    if mouse_pos then
        marks_plus_next:insert(Point(mouse_pos))
    end

    for _, mark in ipairs(marks_plus_next) do
        min_x = math.min(min_x, mark.x)
        max_x = math.max(max_x, mark.x)
        min_y = math.min(min_y, mark.y)
        max_y = math.max(max_y, mark.y)
        min_z = math.min(min_z, mark.z)
        max_z = math.max(max_z, mark.z)
    end

    return { x1 = min_x, y1 = min_y, z1 = min_z, x2 = max_x, y2 = max_y, z2 = max_z }
end

-- TODO Function is too long
function Design:onRenderFrame(dc, rect)

    if (SHOW_DEBUG_WINDOW) then
        self.parent_view.debug_window:updateLayout()
    end

    Design.super.onRenderFrame(self, dc, rect)

    if not self.shape then
        self.shape = shapes.all_shapes[self.subviews.shape_name:getOptionValue()]
    end

    local mouse_pos = dfhack.gui.getMousePos()

    self.subviews.marks_panel:update_mark_labels()

    if self.placing_mark.active and self.placing_mark.index and mouse_pos then
        self.marks[self.placing_mark.index] = Point(mouse_pos)
    end


    -- Set the pos of the currently moving extra point
    if self.placing_extra.active then
        self.extra_points[self.placing_extra.index] = Point(mouse_pos)
    end

    if self.placing_mirror and mouse_pos then
        if not self.mirror_point or Point(mouse_pos) ~= self.mirror_point then
            self.needs_update = true
        end
        self.mirror_point = Point(mouse_pos)
    end

    -- Check if moving center, if so shift the shape by the delta between the previous and current points
    -- TODO clean this up
    if self.prev_center and
        ((self.shape.basic_shape and #self.marks == self.shape.max_points) or
            (not self.shape.basic_shape and not self.placing_mark.active))
        and mouse_pos and self.prev_center ~= Point(mouse_pos) then

        self.needs_update = true

        local transform = Point(mouse_pos) - self.prev_center

        self.marks:transform(transform)
        self.extra_points:transform(transform)

        if self.mirror_point then
            self.mirror_point = Point(self.mirror_point) + transform
        end

        self.prev_center = Point(mouse_pos)
    end
    -- Set main points
    local points = self.marks:copy()

    if self.mirror_point then
        points = self:get_mirrored_points(points)
    end

    if self:shape_needs_update() then
        self.shape:update(points, self.extra_points)
        self.last_mouse_point = Point(mouse_pos)
        self.needs_update = false
    end

    self:add_shape_options()

    -- Show mouse guidelines
    if self.show_guides and mouse_pos then
        local map_x, map_y, _ = dfhack.maps.getTileSize()
        local horiz_bounds = { x1 = 0, x2 = map_x, y1 = mouse_pos.y, y2 = mouse_pos.y, z1 = mouse_pos.z, z2 = mouse_pos.z }
        guidm.renderMapOverlay(function() return guide_tile_pen end, horiz_bounds)
        local vert_bounds = { x1 = mouse_pos.x, x2 = mouse_pos.x, y1 = 0, y2 = map_y, z1 = mouse_pos.z, z2 = mouse_pos.z }
        guidm.renderMapOverlay(function() return guide_tile_pen end, vert_bounds)
    end

    -- Show Mirror guidelines
    if self.mirror_point then
        local mirror_horiz_value = self.subviews.mirror_horiz_label:getOptionValue()
        local mirror_diag_value = self.subviews.mirror_diag_label:getOptionValue()
        local mirror_vert_value = self.subviews.mirror_vert_label:getOptionValue()

        local map_x, map_y, _ = dfhack.maps.getTileSize()

        if mirror_horiz_value ~= 1 or mirror_diag_value ~= 1 then
            local horiz_bounds = {
                x1 = 0, x2 = map_x,
                y1 = self.mirror_point.y, y2 = self.mirror_point.y,
                z1 = self.mirror_point.z, z2 = self.mirror_point.z
            }
            guidm.renderMapOverlay(function() return mirror_guide_pen end, horiz_bounds)
        end

        if mirror_vert_value ~= 1 or mirror_diag_value ~= 1 then
            local vert_bounds = {
                x1 = self.mirror_point.x, x2 = self.mirror_point.x,
                y1 = 0, y2 = map_y,
                z1 = self.mirror_point.z, z2 = self.mirror_point.z
            }
            guidm.renderMapOverlay(function() return mirror_guide_pen end, vert_bounds)
        end
    end

    local vp = guidm.Viewport.get()
    local dscreen = dfhack.screen
    -- use pairs because shape.arr is a sparse matrix so ipairs doesn't work
    for x, _ in pairs(self.shape.arr) do
        for y, _ in pairs(self.shape.arr[x]) do
            if not (x < vp.x1 or x > vp.x2 or y < vp.y1 or y > vp.y2) and self.shape.arr[x][y] then
                local stile = vp:tileToScreen(xyz2pos(x, y, df.global.window_z))
                local point = Point { x = x, y = y }
                local overlay_pen, char, tile = self.pen_cache:get_pen(point)
                if overlay_pen then
                    dscreen.paintTile(overlay_pen, stile.x, stile.y, char, tile, true)
                end
            end
        end
    end

    for i, mark in ipairs(self.marks) do
        local point = mark
        local stile = vp:tileToScreen(xyz2pos(point.x, point.y, df.global.window_z))
        local overlay_pen, char, tile = self.pen_cache:get_pen(point)
        if overlay_pen then
            dscreen.paintTile(overlay_pen, stile.x, stile.y, char, tile, true)
        end
    end
    for i, mark in ipairs(self.extra_points) do
        local point = mark
        local stile = vp:tileToScreen(xyz2pos(point.x, point.y, df.global.window_z))
        local overlay_pen, char, tile = self.pen_cache:get_pen(point)
        if overlay_pen then
            dscreen.paintTile(overlay_pen, stile.x, stile.y, char, tile, true)
        end
    end

    self:updateLayout()
end

-- TODO function too long
function Design:onInput(keys)
    if Design.super.onInput(self, keys) then
        return true
    end

    -- Secret shortcut to kill the panel if it becomes
    -- unresponsive during development, should not release
    if keys.CUSTOM_SHIFT_Q then
        return true
    end

    if keys.LEAVESCREEN or keys._MOUSE_R_DOWN then
        -- Close help window if open
        if view.help_window.visible then self:dismiss_help() return true end

        -- If center draggin, put the shape back to the original center
        if self.prev_center then
            -- jcoskerTODO
            local transform = self.start_center - self.prev_center

            self.marks:transform(transform)

            self.extra_points:transform(transform)

            self.prev_center = nil
            self.start_center = nil
            self.needs_update = true
            return true
        end -- TODO

        -- If extra points, clear them and return
        if self.shape then
            if #self.extra_points > 0 or self.placing_extra.active then
                self.extra_points:clear()
                self.placing_extra.active = false
                self.prev_center = nil
                self.start_center = nil
                self.placing_extra.index = 0
                self.needs_update = true
                self:updateLayout()
                return true
            end
        end

        -- If marks are present, pop the last mark
        if #self.marks > 1 then
            --jcoskerTODO
            self.placing_mark.index = #self.marks - ((self.placing_mark.active) and 1 or 0)
            self.placing_mark.active = true
            self.needs_update = true
            self.marks:remove()
        else
            -- nothing left to remove, so dismiss
            self.parent_view:dismiss()
        end

        return true
    end


    local pos = nil
    if keys._MOUSE_L_DOWN and not self:getMouseFramePos() then
        pos = dfhack.gui.getMousePos()
        if pos then
            guidm.setCursorPos(pos)
        end
    elseif keys.SELECT then
        pos = guidm.getCursorPos()
    end

    if keys._MOUSE_L_DOWN and pos then
        -- TODO Refactor this a bit
        if self.shape.max_points and #self.marks == self.shape.max_points and self.placing_mark.active then
            self.marks[self.placing_mark.index] = Point(pos)
            self.placing_mark.index = self.placing_mark.index + 1
            self.placing_mark.active = false
            -- The statement after the or is to allow the 1x1 special case for easy doorways
            self.needs_update = true
            if self.autocommit or (self.marks[1] == self.marks[2]) then
                self:commit()
            end
        elseif not self.placing_extra.active and self.placing_mark.active then
            self.marks[self.placing_mark.index] = Point(pos)
            if self.placing_mark.continue then
                self.placing_mark.index = self.placing_mark.index + 1
            else
                self.placing_mark.index = nil
                self.placing_mark.active = false
            end
            self.needs_update = true
        elseif self.placing_extra.active then
            self.needs_update = true
            self.placing_extra.active = false
        elseif self.placing_mirror then
            self.mirror_point = Point(pos)
            self.placing_mirror = false
            self.needs_update = true
        else
            if self.shape.basic_shape and #self.marks == self.shape.max_points then
                -- Clicking a corner of a basic shape
                --jcoskerTODO
                local shape_top_left, shape_bot_right = self.shape:get_point_dims()
                local corner_drag_info = {
                    { pos = shape_top_left, opposite_x = shape_bot_right.x, opposite_y = shape_bot_right.y, corner = "nw" },
                    { pos = xy2pos(shape_bot_right.x, shape_top_left.y), opposite_x = shape_top_left.x,
                        opposite_y = shape_bot_right.y, corner = "ne" },
                    { pos = xy2pos(shape_top_left.x, shape_bot_right.y), opposite_x = shape_bot_right.x,
                        opposite_y = shape_top_left.y, corner = "sw" },
                    { pos = shape_bot_right, opposite_x = shape_top_left.x, opposite_y = shape_top_left.y, corner = "se" }
                }

                for _, info in ipairs(corner_drag_info) do
                    if Point(pos) == Point(info.pos) and self.shape.drag_corners[info.corner] then
                        self.marks[1] = Point { x = info.opposite_x, y = info.opposite_y, z = self.marks[1].z }
                        self.marks:remove(2) -- jcoskerTODO
                        self.placing_mark = { active = true, index = 2 }
                        break
                    end
                end
            else
                for i, point in ipairs(self.marks) do
                    if Point(pos) == point then
                        self.placing_mark = { active = true, index = i, continue = false }
                    end
                end
            end

            -- Clicking an extra point
            for i = 1, #self.extra_points do
                if Point(pos) == self.extra_points[i] then
                    self.placing_extra = { active = true, index = i }
                    self.needs_update = true
                    return true
                end
            end

            -- Clicking center point
            if #self.marks > 0 then
                local center = self.shape:get_center()
                if Point(pos) == center and not self.prev_center then
                    self.start_center = Point(pos)
                    self.prev_center = Point(pos)
                    return true
                elseif self.prev_center then
                    self.start_center = nil
                    self.prev_center = nil
                    return true
                end
            end

            if self.mirror_point == Point(pos) then
                self.placing_mirror = true
            end
        end

        self.needs_update = true
        return true
    end

    -- send movement and pause keys through, but otherwise we're a modal dialog
    return not (keys.D_PAUSE or guidm.getMapKey(keys))
end

-- Put any special logic for designation type here
-- Right now it's setting the stair type based on the z-level
-- Fell through, pass through the option directly from the options value
function Design:get_designation(x, y, z)
    local mode = self.subviews.mode_name:getOptionValue()

    local view_bounds = self:get_view_bounds()
    local top_left, bot_right = self.shape:get_true_dims()

    -- Stairs
    if mode.desig == "i" then
        local stairs_top_type = self.subviews.stairs_top_subtype:getOptionValue()
        local stairs_middle_type = self.subviews.stairs_middle_subtype:getOptionValue()
        local stairs_bottom_type = self.subviews.stairs_bottom_subtype:getOptionValue()
        if z == 0 then
            return stairs_bottom_type == "auto" and "u" or stairs_bottom_type
        elseif view_bounds and z == math.abs(view_bounds.z1 - view_bounds.z2) then
            local pos = Point { x = view_bounds.x1 + x, y = view_bounds.y1 + y, z = view_bounds.z1 + z }
            local tile_type = dfhack.maps.getTileType(pos)
            local tile_shape = tile_type and tile_attrs[tile_type].shape or nil
            local designation = dfhack.maps.getTileFlags(pos) -- jcoskerTODO check

            -- If top of the view_bounds is down stair, 'auto' should change it to up/down to match vanilla stair logic
            local up_or_updown_dug = (
                tile_shape == df.tiletype_shape.STAIR_DOWN or tile_shape == df.tiletype_shape.STAIR_UPDOWN)
            local up_or_updown_desig = designation and (designation.dig == df.tile_dig_designation.UpStair or
                designation.dig == df.tile_dig_designation.UpDownStair)

            if stairs_top_type == "auto" then
                return (up_or_updown_desig or up_or_updown_dug) and "i" or "j"
            else
                return stairs_top_type
            end
        else
            return stairs_middle_type == "auto" and 'i' or stairs_middle_type
        end
    elseif mode.desig == "b" then
        local building_outer_tiles = self.subviews.building_outer_tiles:getOptionValue()
        local building_inner_tiles = self.subviews.building_inner_tiles:getOptionValue()
        local darr = { { 1, 1 }, { 1, 0 }, { 0, 1 }, { 0, 0 }, { -1, 0 }, { -1, -1 }, { 0, -1 }, { 1, -1 }, { -1, 1 } }

        -- If not completed surrounded, then use outer tile
        for i, d in ipairs(darr) do
            if not (self.shape:get_point(top_left.x + x + d[1], top_left.y + y + d[2])) then
                return building_outer_tiles
            end
        end

        -- Is inner tile
        return building_inner_tiles
    end

    return mode.desig
end

-- Commit the shape using quickfort API
function Design:commit()
    local data = {}
    local top_left, bot_right = self.shape:get_true_dims()
    local view_bounds = self:get_view_bounds()

    -- Means mo marks set
    if not view_bounds then return end

    local mode = self.subviews.mode_name:getOptionValue().mode
    -- Generates the params for quickfort API
    local function generate_params(grid, position)
        -- local top_left, bot_right = self.shape:get_true_dims()
        for zlevel = 0, math.abs(view_bounds.z1 - view_bounds.z2) do
            data[zlevel] = {}
            for row = 0, math.abs(bot_right.y - top_left.y) do
                data[zlevel][row] = {}
                for col = 0, math.abs(bot_right.x - top_left.x) do
                    if grid[col] and grid[col][row] then
                        local desig = self:get_designation(col, row, zlevel)
                        if desig ~= "`" then
                            data[zlevel][row][col] =
                            desig .. (mode ~= "build" and tostring(self.prio) or "")
                        end
                    end
                end
            end
        end

        return {
            data = data,
            pos = position,
            mode = mode,
        }
    end

    local start = {
        x = top_left.x,
        y = top_left.y,
        z = math.min(view_bounds.z1, view_bounds.z2),
    }

    local grid = self.shape:transform(0, 0)

    -- Special case for 1x1 to ease doorway marking
    if Point(top_left) == Point(bot_right) then
        grid = {}
        grid[0] = {}
        grid[0][0] = true
    end

    local params = generate_params(grid, start)
    quickfort.apply_blueprint(params)

    -- Only clear points if we're autocommit, or if we're doing a complex shape and still placing
    if (self.autocommit and self.shape.basic_shape) or
        (not self.shape.basic_shape and
            (self.placing_mark.active or (self.autocommit and self.shape.max_points == #self.marks))) then
        self.marks:clear()
        self.placing_mark = { active = true, index = 1, continue = true }
        self.placing_extra = { active = false, index = nil }
        self.extra_points:clear()
        self.prev_center = nil
        self.start_center = nil
    end

    self:updateLayout()
end

function Design:get_mirrored_points(points)
    local mirror_horiz_value = self.subviews.mirror_horiz_label:getOptionValue()
    local mirror_diag_value = self.subviews.mirror_diag_label:getOptionValue()
    local mirror_vert_value = self.subviews.mirror_vert_label:getOptionValue()

    local mirrored_points = Points {}
    for i = #points, 1, -1 do
        local point = points[i]
        -- 1 maps to "Off"
        if mirror_horiz_value ~= 1 then
            local mirrored_y = self.mirror_point.y + ((self.mirror_point.y - point.y))

            -- if Mirror (even), then increase mirror amount by 1
            if mirror_horiz_value == 3 then
                if mirrored_y > self.mirror_point.y then
                    mirrored_y = mirrored_y + 1
                else
                    mirrored_y = mirrored_y - 1
                end
            end

            mirrored_points:insert(Point { z = point.z, x = point.x, y = mirrored_y })
        end
    end

    for i, point in ipairs(points) do
        if mirror_diag_value ~= 1 then
            local mirrored_y = self.mirror_point.y + ((self.mirror_point.y - point.y))
            local mirrored_x = self.mirror_point.x + ((self.mirror_point.x - point.x))

            -- if Mirror (even), then increase mirror amount by 1
            if mirror_diag_value == 3 then
                if mirrored_y > self.mirror_point.y then
                    mirrored_y = mirrored_y + 1
                    mirrored_x = mirrored_x + 1
                else
                    mirrored_y = mirrored_y - 1
                    mirrored_x = mirrored_x - 1
                end
            end

            mirrored_points:insert(Point { z = point.z, x = mirrored_x, y = mirrored_y })
        end
    end

    for i = #points, 1, -1 do
        local point = points[i]
        if mirror_vert_value ~= 1 then
            local mirrored_x = self.mirror_point.x + ((self.mirror_point.x - point.x))

            -- if Mirror (even), then increase mirror amount by 1
            if mirror_vert_value == 3 then
                if mirrored_x > self.mirror_point.x then
                    mirrored_x = mirrored_x + 1
                else
                    mirrored_x = mirrored_x - 1
                end
            end

            mirrored_points:insert(Point { z = point.z, x = mirrored_x, y = point.y })
        end
    end

    for i, point in ipairs(mirrored_points) do
        points:insert(mirrored_points[i])
    end

    return points
end

function Design:show_help(text)
    self.parent_view.help_window.message = text
    self.parent_view.help_window.visible = true
    self.parent_view:updateLayout()
end

function Design:dismiss_help()
    self.parent_view.help_window.visible = false
end

--
-- DesignScreen
--

DesignScreen = defclass(DesignScreen, gui.ZScreen)
DesignScreen.ATTRS {
    focus_path = "design",
    pass_pause = true,
    pass_movement_keys = true,
}

function DesignScreen:init()

    self.design_window = Design {}
    self.help_window = HelpWindow {}
    self.help_window.visible = false
    self:addviews { self.design_window, self.help_window }
    if SHOW_DEBUG_WINDOW then
        self.debug_window = DesignDebugWindow { design_window = self.design_window }
        self:addviews { self.debug_window }
    end
end

function DesignScreen:onDismiss()
    view = nil
end

if dfhack_flags.module then return end

if not dfhack.isMapLoaded() then
    qerror("This script requires a fortress map to be loaded")
end

view = view and view:raise() or DesignScreen {}:show()
