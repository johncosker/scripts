-- A GUI front-end for creating designs
--@ module = true

local shapes = reqscript("internal/design/shapes")
-- local gui = require("gui")
-- local guidm = require("gui.dwarfmode")
local widgets = require("gui.widgets")

--Show mark point coordinates
MarksPanel = defclass(MarksPanel, widgets.ResizingPanel)
MarksPanel.ATTRS {
    autoarrange_subviews = true,
    design_panel = DEFAULT_NIL
}

function MarksPanel:init()
end

function MarksPanel:update_mark_labels()
    self.subviews = {}
    local label_text = {}
    if #self.design_panel.marks >= 1 then
        local first_mark = self.design_panel.marks[1]
        if first_mark then
            table.insert(label_text,
                string.format("First Mark (%d): %d, %d, %d ", 1, first_mark.x, first_mark.y, first_mark.z))
        end
    end

    if #self.design_panel.marks > 1 then
        local last_mark = self.design_panel.marks[#self.design_panel.marks]
        if last_mark then
            table.insert(label_text,
                string.format("Last Mark (%d): %d, %d, %d ", #self.design_panel.marks, last_mark.x, last_mark.y,
                    last_mark.z))
        end
    end

    local mouse_pos = dfhack.gui.getMousePos()
    if mouse_pos then
        -- jcoskerTODO
        table.insert(label_text, string.format("Mouse: %d, %d, %d", mouse_pos.x, mouse_pos.y, mouse_pos.z))
    end

    local mirror = self.design_panel.mirror_point
    if mirror then
        table.insert(label_text, string.format("Mirror Point: %d, %d, %d", mirror.x, mirror.y, mirror.z))
    end

    self:addviews {
        widgets.WrappedLabel {
            view_id = "mark_labels",
            text_to_wrap = label_text,
        }
    }
end

-- Panel to show the Mouse position/dimensions/etc
ActionPanel = defclass(ActionPanel, widgets.ResizingPanel)
ActionPanel.ATTRS {
    autoarrange_subviews = true,
    design_panel = DEFAULT_NIL
}

function ActionPanel:init()
    self:addviews {
        widgets.WrappedLabel {
            view_id = "action_label",
            text_to_wrap = self:callback("get_action_text"),
        },
        widgets.WrappedLabel {
            view_id = "selected_area",
            text_to_wrap = self:callback("get_area_text"),
        },
        self:get_mark_labels()
    }
end

function ActionPanel:get_mark_labels()
end

function ActionPanel:get_action_text()
    local text = ""
    if self.design_panel.marks[1] and self.design_panel.placing_mark.active then
        text = "Place the next point"
    elseif not self.design_panel.marks[1] then
        text = "Place the first point"
    elseif not self.parent_view.placing_extra.active and not self.parent_view.prev_center then
        text = "Select any draggable points"
    elseif self.parent_view.placing_extra.active then
        text = "Place any extra points"
    elseif self.parent_view.prev_center then
        text = "Place the center point"
    else
        text = "Select any draggable points"
    end
    return text.." with the mouse. Use right-click to dismiss points in order."
end

function ActionPanel:get_area_text()
    local label = "Area: "

    local bounds = self.design_panel:get_view_bounds()
    if not bounds then return label.."N/A" end
    local width = math.abs(bounds.x2 - bounds.x1) + 1
    local height = math.abs(bounds.y2 - bounds.y1) + 1
    local depth = math.abs(bounds.z2 - bounds.z1) + 1
    local tiles = self.design_panel.shape.num_tiles * depth
    local plural = tiles > 1 and "s" or ""
    return label..("%dx%dx%d (%d tile%s)"):format(
        width,
        height,
        depth,
        tiles,
        plural
    )
end

function ActionPanel:get_mark_text(num)
    local mark = self.design_panel.marks[num]

    local label = string.format("Mark %d: ", num)

    if not mark then
        return label.."Not set"
    end

    return label..("%d, %d, %d"):format(
        mark.x,
        mark.y,
        mark.z
    )
end

-- Generic options not specific to shapes
GenericOptionsPanel = defclass(GenericOptionsPanel, widgets.ResizingPanel)
GenericOptionsPanel.ATTRS {
    name = DEFAULT_NIL,
    autoarrange_subviews = true,
    design_panel = DEFAULT_NIL,
    on_layout_change = DEFAULT_NIL,
}

function GenericOptionsPanel:init()
    local options = {}
    for i, shape in ipairs(shapes.all_shapes) do
        options[#options + 1] = {
            label = shape.name,
            value = i,
        }
    end

    local stair_options = {
        {
            label = "Auto",
            value = "auto",
        },
        {
            label = "Up/Down",
            value = "i",
        },
        {
            label = "Up",
            value = "u",
        },
        {
            label = "Down",
            value = "j",
        },
    }

    local build_options = {
        {
            label = "Walls",
            value = "Cw",
        },
        {
            label = "Floor",
            value = "Cf",
        },
        {
            label = "Fortification",
            value = "CF",
        },
        {
            label = "Ramps",
            value = "Cr",
        },
        {
            label = "None",
            value = "`",
        },
    }

    self:addviews {
        widgets.WrappedLabel {
            view_id = "settings_label",
            text_to_wrap = "General Settings:\n",
        },
        widgets.CycleHotkeyLabel {
            view_id = "shape_name",
            key = "CUSTOM_Z",
            key_back = "CUSTOM_SHIFT_Z",
            label = "Shape: ",
            label_width = 8,
            options = options,
            on_change = self:callback("change_shape"),
        },

        widgets.ResizingPanel { autoarrange_subviews = true,
            subviews = {
                widgets.ToggleHotkeyLabel {
                    key = 'CUSTOM_SHIFT_Y',
                    view_id = 'transform',
                    label = 'Transform',
                    enabled = true,
                    initial_option = false,
                    on_change = nil
                },
                widgets.ResizingPanel {
                    view_id = 'transform_panel_rotate',
                    visible = function() return self.design_panel.subviews.transform:getOptionValue() end,
                    subviews = {
                        widgets.HotkeyLabel {
                            key = 'STRING_A040',
                            frame = { t = 1, l = 1 }, key_sep = '',
                            on_activate = self.design_panel:callback('on_transform', 'ccw'),
                        },
                        widgets.HotkeyLabel {
                            key = 'STRING_A041',
                            frame = { t = 1, l = 2 }, key_sep = ':',
                            on_activate = self.design_panel:callback('on_transform', 'cw'),
                        },
                        widgets.WrappedLabel {
                            frame = { t = 1, l = 5 },
                            text_to_wrap = 'Rotate'
                        },
                        widgets.HotkeyLabel {
                            key = 'STRING_A095',
                            frame = { t = 2, l = 1 }, key_sep = '',
                            on_activate = self.design_panel:callback('on_transform', 'flipv'),
                        },
                        widgets.HotkeyLabel {
                            key = 'STRING_A061',
                            frame = { t = 2, l = 2 }, key_sep = ':',
                            on_activate = self.design_panel:callback('on_transform', 'fliph'),
                        },
                        widgets.WrappedLabel {
                            frame = { t = 2, l = 5 },
                            text_to_wrap = 'Flip'
                        }
                    }
                }
            }
        },
        widgets.ResizingPanel { autoarrange_subviews = true,
            subviews = {
                widgets.HotkeyLabel {
                    key = 'CUSTOM_M',
                    view_id = 'mirror_point_panel',
                    visible = function() return self.design_panel.shape.can_mirror end,
                    label = function() if not self.design_panel.mirror_point then return 'Place Mirror Point' else return 'Delete Mirror Point' end end,
                    enabled = function() return not self.design_panel.placing_extra.active and
                            not self.design_panel.placing_mark.active and not self.prev_center
                    end,
                    on_activate = function()
                        if not self.design_panel.mirror_point then
                            self.design_panel.placing_mark.active = false
                            self.design_panel.placing_extra.active = false
                            self.design_panel.placing_extra.active = false
                            self.design_panel.placing_mirror = true
                        else
                            self.design_panel.placing_mirror = false
                            self.design_panel.mirror_point = nil
                        end
                    end
                },
                widgets.ResizingPanel {
                    view_id = 'transform_panel_rotate',
                    visible = function() return self.design_panel.mirror_point end,
                    subviews = {
                        widgets.CycleHotkeyLabel {
                            view_id = "mirror_horiz_label",
                            key = "CUSTOM_SHIFT_J",
                            label = "Mirror Horizontal: ",
                            enabled = true,
                            initial_option = 1,
                            options = { { label = "Off", value = 1 }, { label = "On (odd)", value = 2 },
                                { label = "On (even)", value = 3 } },
                            frame = { t = 1, l = 1 }, key_sep = '',
                            on_change = function() self.design_panel.needs_update = true end
                        },
                        widgets.CycleHotkeyLabel {
                            view_id = "mirror_diag_label",
                            key = "CUSTOM_SHIFT_O",
                            label = "Mirror Diagonal: ",
                            enabled = true,
                            initial_option = 1,
                            options = { { label = "Off", value = 1 }, { label = "On (odd)", value = 2 },
                                { label = "On (even)", value = 3 } },
                            frame = { t = 2, l = 1 }, key_sep = '',
                            on_change = function() self.design_panel.needs_update = true end
                        },
                        widgets.CycleHotkeyLabel {
                            view_id = "mirror_vert_label",
                            key = "CUSTOM_SHIFT_K",
                            label = "Mirror Vertical: ",
                            enabled = true,
                            initial_option = 1,
                            options = { { label = "Off", value = 1 }, { label = "On (odd)", value = 2 },
                                { label = "On (even)", value = 3 } },
                            frame = { t = 3, l = 1 }, key_sep = '',
                            on_change = function() self.design_panel.needs_update = true end
                        },
                        widgets.HotkeyLabel {
                            view_id = "mirror_vert_label",
                            key = "CUSTOM_SHIFT_M",
                            label = "Save Mirrored Points",
                            enabled = true,
                            initial_option = 1,
                            frame = { t = 4, l = 1 }, key_sep = ': ',
                            on_activate = function()
                                local points = self.design_panel:get_mirrored_points(self.design_panel.marks)
                                self.design_panel.marks = points
                                self.design_panel.mirror_point = nil
                            end
                        },
                    }
                }
            }
        },
        widgets.ToggleHotkeyLabel {
            view_id = "invert_designation_label",
            key = "CUSTOM_I",
            label = "Invert: ",
            label_width = 8,
            enabled = function()
                return self.design_panel.shape.invertable == true
            end,
            initial_option = false,
            on_change = function(new, old)
                self.design_panel.shape.invert = new
                self.design_panel.needs_update = true
            end,
        },
        widgets.HotkeyLabel {
            view_id = "shape_place_extra_point",
            key = "CUSTOM_V",
            label = function()
                local msg = "Place extra point: "
                if #self.design_panel.extra_points < #self.design_panel.shape.extra_points then
                    return msg..self.design_panel.shape.extra_points[#self.design_panel.extra_points + 1].label
                end

                return msg.."N/A"
            end,
            visible = function() return self.design_panel.shape and #self.design_panel.shape.extra_points > 0 end,
            enabled = function()
                if self.design_panel.shape then
                    return #self.design_panel.extra_points < #self.design_panel.shape.extra_points
                end

                return false
            end,
            on_activate = function()
                if not self.design_panel.placing_mark.active then
                    self.design_panel.placing_extra.active = true
                    self.design_panel.placing_extra.index = #self.design_panel.extra_points + 1
                elseif #self.design_panel.marks then
                    local mouse_pos = dfhack.gui.getMousePos()
                    if mouse_pos then self.design_panel.extra_points:insert(Point(mouse_pos)) end
                end
                self.design_panel.needs_update = true
            end,
        },
        widgets.HotkeyLabel {
            view_id = "shape_toggle_placing_marks",
            key = "CUSTOM_B",
            label = function()
                return (self.design_panel.placing_mark.active) and "Stop placing" or "Start placing"
            end,
            enabled = function()
                if not self.design_panel.placing_mark.active and not self.design_panel.prev_center then
                    return not self.design_panel.shape.max_points or
                        #self.design_panel.marks < self.design_panel.shape.max_points
                elseif not self.design_panel.placing_extra.active and not self.design_panel.prev_centerl then
                    return true
                end

                return false
            end,
            on_activate = function()
                self.design_panel.placing_mark.active = not self.design_panel.placing_mark.active
                self.design_panel.placing_mark.index = (self.design_panel.placing_mark.active) and
                    #self.design_panel.marks + 1 or
                    nil
                if not self.design_panel.placing_mark.active then
                    table.remove(self.design_panel.marks, #self.design_panel.marks)
                else
                    self.design_panel.placing_mark.continue = true
                end

                self.design_panel.needs_update = true
            end,
        },
        widgets.HotkeyLabel {
            view_id = "shape_clear_all_points",
            key = "CUSTOM_X",
            label = "Clear all points",
            enabled = function()
                if #self.design_panel.marks > 0 then return true
                elseif self.design_panel.shape then
                    if #self.design_panel.extra_points < #self.design_panel.shape.extra_points then
                        return true
                    end
                end

                return false
            end,
            disabled = false,
            on_activate = function()
                self.design_panel.marks:clear()
                self.design_panel.placing_mark.active = true
                self.design_panel.placing_mark.index = 1
                self.design_panel.extra_points:clear()
                self.design_panel.prev_center = nil
                self.design_panel.mirror_point = nil
                self.design_panel.start_center = nil
                self.design_panel.needs_update = true
            end,
        },
        widgets.HotkeyLabel {
            view_id = "shape_clear_extra_points",
            key = "CUSTOM_SHIFT_X",
            label = "Clear extra points",
            enabled = function()
                if self.design_panel.shape then
                    if #self.design_panel.extra_points > 0 then
                        return true
                    end
                end

                return false
            end,
            disabled = false,
            visible = function() return self.design_panel.shape and #self.design_panel.shape.extra_points > 0 end,
            on_activate = function()
                if self.design_panel.shape then
                    self.design_panel.extra_points:clear()
                    self.design_panel.prev_center = nil
                    self.design_panel.start_center = nil
                    self.design_panel.placing_extra = { active = false, index = 0 }
                    self.design_panel:updateLayout()
                    self.design_panel.needs_update = true
                end
            end,
        },
        widgets.ToggleHotkeyLabel {
            view_id = "shape_show_guides",
            key = "CUSTOM_SHIFT_G",
            label = "Show Cursor Guides",
            enabled = true,
            initial_option = true,
            on_change = function(new, old)
                self.design_panel.show_guides = new
            end,
        },
        widgets.CycleHotkeyLabel {
            view_id = "mode_name",
            key = "CUSTOM_F",
            key_back = "CUSTOM_SHIFT_F",
            label = "Mode: ",
            label_width = 8,
            enabled = true,
            options = {
                {
                    label = "Dig",
                    value = { desig = "d", mode = "dig" },
                },
                {
                    label = "Channel",
                    value = { desig = "h", mode = "dig" },
                },
                {
                    label = "Remove Designation",
                    value = { desig = "x", mode = "dig" },
                },
                {
                    label = "Remove Ramps",
                    value = { desig = "z", mode = "dig" },
                },
                {
                    label = "Remove Constructions",
                    value = { desig = "n", mode = "dig" },
                },
                {
                    label = "Stairs",
                    value = { desig = "i", mode = "dig" },
                },
                {
                    label = "Ramp",
                    value = { desig = "r", mode = "dig" },
                },
                {
                    label = "Smooth",
                    value = { desig = "s", mode = "dig" },
                },
                {
                    label = "Engrave",
                    value = { desig = "e", mode = "dig" },
                },
                {
                    label = "Building",
                    value = { desig = "b", mode = "build" },
                }
            },
            disabled = false,
            on_change = function(new, old) self.design_panel:updateLayout() end,
        },
        widgets.ResizingPanel {
            view_id = 'stairs_type_panel',
            visible = self:callback("is_mode_selected", "i"),
            subviews = {
                widgets.CycleHotkeyLabel {
                    view_id = "stairs_top_subtype",
                    key = "CUSTOM_R",
                    label = "Top Stair Type: ",
                    frame = { t = 0, l = 1 },
                    enabled = true,
                    options = stair_options,
                },
                widgets.CycleHotkeyLabel {
                    view_id = "stairs_middle_subtype",
                    key = "CUSTOM_G",
                    label = "Middle Stair Type: ",
                    frame = { t = 1, l = 1 },
                    enabled = true,
                    options = stair_options,
                },
                widgets.CycleHotkeyLabel {
                    view_id = "stairs_bottom_subtype",
                    key = "CUSTOM_N",
                    label = "Bottom Stair Type: ",
                    frame = { t = 2, l = 1 },
                    enabled = true,
                    options = stair_options,
                }
            }
        },
        widgets.ResizingPanel {
            view_id = 'building_types_panel',
            visible = self:callback("is_mode_selected", "b"),
            subviews = {
                widgets.Label {
                    view_id = "building_outer_config",
                    frame = { t = 0, l = 1 },
                    text = { { tile = BUTTON_PEN_LEFT }, { tile = HELP_PEN_CENTER }, { tile = BUTTON_PEN_RIGHT } },
                    on_click = self.design_panel:callback("show_help", CONSTRUCTION_HELP)
                },
                widgets.CycleHotkeyLabel {
                    view_id = "building_outer_tiles",
                    key = "CUSTOM_R",
                    label = "Outer Tiles: ",
                    frame = { t = 0, l = 5 },
                    enabled = true,
                    initial_option = 1,
                    options = build_options,
                },
                widgets.Label {
                    view_id = "building_inner_config",
                    frame = { t = 1, l = 1 },
                    text = { { tile = BUTTON_PEN_LEFT }, { tile = HELP_PEN_CENTER }, { tile = BUTTON_PEN_RIGHT } },
                    on_click = self.design_panel:callback("show_help", CONSTRUCTION_HELP)
                },
                widgets.CycleHotkeyLabel {
                    view_id = "building_inner_tiles",
                    key = "CUSTOM_G",
                    label = "Inner Tiles: ",
                    frame = { t = 1, l = 5 },
                    enabled = true,
                    initial_option = 2,
                    options = build_options,
                },
            },
        },
        widgets.WrappedLabel {
            view_id = "shape_prio_label",
            text_to_wrap = function()
                return "Priority: "..tostring(self.design_panel.prio)
            end,
        },
        widgets.HotkeyLabel {
            view_id = "shape_option_priority_minus",
            key = "CUSTOM_P",
            label = "Increase Priority",
            enabled = function()
                return self.design_panel.prio > 1
            end,
            disabled = false,
            on_activate = function()
                self.design_panel.prio = self.design_panel.prio - 1
                self.design_panel:updateLayout()
                self.design_panel.needs_update = true
            end,
        },
        widgets.HotkeyLabel {
            view_id = "shape_option_priority_plus",
            key = "CUSTOM_SHIFT_P",
            label = "Decrease Priority",
            enabled = function()
                return self.design_panel.prio < 7
            end,
            disabled = false,
            on_activate = function()
                self.design_panel.prio = self.design_panel.prio + 1
                self.design_panel:updateLayout()
                self.design_panel.needs_update = true
            end,
        },
        widgets.ToggleHotkeyLabel {
            view_id = "autocommit_designation_label",
            key = "CUSTOM_C",
            label = "Auto-Commit: ",
            enabled = function() return self.design_panel.shape.max_points end,
            disabled = false,
            initial_option = true,
            on_change = function(new, old)
                self.design_panel.autocommit = new
                self.design_panel.needs_update = true
            end,
        },
        widgets.HotkeyLabel {
            view_id = "commit_label",
            key = "CUSTOM_CTRL_C",
            label = "Commit Designation",
            enabled = function()
                return #self.design_panel.marks >= self.design_panel.shape.min_points
            end,
            disabled = false,
            on_activate = function()
                self.design_panel:commit()
                self.design_panel.needs_update = true
            end,
        },
    }
end

function GenericOptionsPanel:is_mode_selected(mode)
    return self.design_panel.subviews.mode_name:getOptionValue().desig == mode
end

function GenericOptionsPanel:change_shape(new, old)
    self.design_panel.shape = shapes.all_shapes[new]
    if self.design_panel.shape.max_points and #self.design_panel.marks > self.design_panel.shape.max_points then
        -- pop marks until we're down to the max of the new shape
        for i = #self.design_panel.marks, self.design_panel.shape.max_points, -1 do
            table.remove(self.design_panel.marks, i)
        end
    end
    self.design_panel:add_shape_options()
    self.design_panel.needs_update = true
    self.design_panel:updateLayout()
end
