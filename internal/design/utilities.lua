-- Utilities for design.lua
--@ module = true

local to_pen = dfhack.pen.parse

-- Point class used by gui/design
Point = defclass(Point)
Point.ATTRS {
    x = DEFAULT_NIL,
    y = DEFAULT_NIL,
    z = DEFAULT_NIL
}

function Point:init()
    -- setmetatable(self, {__tostring = function() return tostring(self.x)..","..tostring(self.y)..","..tostring(self.z)end})
    self:check_valid()
end

function Point:check_valid(point)
    point = point or self
    if not point.x or not point.y then error("Invalid Point: x and y values are required") end
    if not type(point.x) == "number" then error("Invalid value for x, must be a number") end
    if not type(point.y) == "number" then error("Invalid value for y, must be a number") end
    if point.z and not type(point.y) == "number" then error("Invalid value for z, must be a number") end
end

function Point:is_mouse_over()
    local pos = dfhack.gui.getMousePos()
    if not pos then return false end

    return Point(pos) == self
end

function Point:__call(args)
    if type(args[1]) == "table" then
        if args[1].x then self.x = args[1].x end
        if args[1].y then self.y = args[1].y end
        if args[1].z then self.z = args[1].z end
    end
end

function Point:__tostring()
    return "("..tostring(self.x)..", "..tostring(self.y)..", "..tostring(self.z)..")"
end

-- todo __concat for strings or tables or whatevers
function Point:get_add_sub_table(arg)
    local t_other = { x = 0, y = 0, z = 0 }

    if type(arg) == "number" then
        t_other = Point { x = arg, y = arg } -- As of now we don't want to add anything to z unless explicit
    elseif type(arg) == "table" then
        if not (arg.x ~= nil or arg.y ~= nil or arg.z ~= nil) then
            error("Adding table that doesn't have x, y or z values.")
        end
        if arg.x then
            if type(arg.x) == "number" then
                t_other.x = arg.x
            end
        end
        if arg.y then
            if type(arg.y) == "number" then
                t_other.y = arg.y
            end
        end
        if arg.z then
            if type(arg.z) == "number" then
                t_other.z = arg.z
            end
        end
    end

    return t_other
end

function Point:__add(arg)
    local t_other = self:get_add_sub_table(arg)
    return Point { x = self.x + t_other.x, y = self.y + t_other.y, (self.z and t_other.z) and self.z + t_other.z or nil }
end

function Point:__sub(arg)
    local t_other = self:get_add_sub_table(arg)
    return Point { x = self.x - t_other.x, y = self.y - t_other.y, z = (self.z and t_other.z) and self.z - t_other.z or nil}
end

-- For the purposes of GUI design, we only care about x and y being equal, z is only used for determining boundaries and x levels to apply the shape
function Point:__eq(other)
    self:check_valid(other)
    return self.x == other.x and self.y == other.y
end

-- Stack-like collection for points
Points = defclass(Points)
Points.ATTRS {
    -- points = DEFAULT_NIL
}

function Points:init()
    rawset(self, 'points', {})
end

function Points:clear()
    rawset(self, 'points', {})
end

function Points:transform(transform)
    for i, point in ipairs(self.points) do
        self.points[i] = point + transform
    end
end

function Points:insert(index)
    if index then
        table.insert(self.points, index)
    else
        table.insert(self.points)
    end
end

function Points:remove(index)
    if index then
        table.remove(self.points, index)
    else
        table.remove(self.points)
    end
end

function Points:copy()
    local copy = Points {}
    for _, point in ipairs(self.points) do
        copy:insert(point)
    end
    local meta_table = getmetatable(self)
    setmetatable(copy, meta_table)

    return copy
end

function Points:__len()
    return #rawget(self, 'points')
end

function Points:__index(key)
    -- Check if the key exists in the class itself
    local class_value = rawget(getmetatable(self), key)
    if class_value ~= nil then
        return class_value
    end

    -- Check if the key exists in the 'points' table
    local value = rawget(self, 'points')[key]
    return value
end

function Points:__newindex(key, value)
    if type(key) == "number" then
        local p = Point(value)
        self.points[key] = p
        return
    end

    -- if key == 'points' then self.points = value return end

    error("Points class table fields not meant to be modified during runtime.")
end

PenCache = defclass(PenCache)
PenCache.ATTRS = {
    is_drag_pt_fn = DEFAULT_NIL,
    is_extra_pt_fn = DEFAULT_NIL,
    get_arr_fn = DEFAULT_NIL,
    pens = {},
    pen_mask = {
        NORTH = 1,
        SOUTH = 2,
        EAST = 3,
        WEST = 4,
        DRAG_POINT = 5,
        MOUSEOVER = 6,
        INSHAPE = 7,
        EXTRA_POINT = 8,
    },
    cursors = {
        INSIDE = { 1, 2 },
        NORTH = { 1, 1 },
        N_NUB = { 3, 2 },
        S_NUB = { 4, 2 },
        W_NUB = { 3, 1 },
        E_NUB = { 5, 1 },
        NE = { 2, 1 },
        NW = { 0, 1 },
        WEST = { 0, 2 },
        EAST = { 2, 2 },
        SW = { 0, 3 },
        SOUTH = { 1, 3 },
        SE = { 2, 3 },
        VERT_NS = { 3, 3 },
        VERT_EW = { 4, 1 },
        POINT = { 4, 3 },
    }

}

function PenCache:init()
end

-- Generate a bit field to store as keys in PENS
function PenCache:gen_pen_key(n, s, e, w, is_corner, is_mouse_over, inshape, extra_point)
    local ret = 0
    if n then ret = ret + (1 << self.pen_mask.NORTH) end
    if s then ret = ret + (1 << self.pen_mask.SOUTH) end
    if e then ret = ret + (1 << self.pen_mask.EAST) end
    if w then ret = ret + (1 << self.pen_mask.WEST) end
    if is_corner then ret = ret + (1 << self.pen_mask.DRAG_POINT) end
    if is_mouse_over then ret = ret + (1 << self.pen_mask.MOUSEOVER) end
    if inshape then ret = ret + (1 << self.pen_mask.INSHAPE) end
    if extra_point then ret = ret + (1 << self.pen_mask.EXTRA_POINT) end

    return ret
end

-- return the pen, alter based on if we want to display a corner and a mouse over corner
function PenCache:make_pen(direction, is_corner, is_mouse_over, inshape, extra_point)

    local color = COLOR_GREEN
    local ycursor_mod = 0
    if not extra_point then
        if is_corner then
            color = COLOR_CYAN
            ycursor_mod = ycursor_mod + 6
            if is_mouse_over then
                color = COLOR_MAGENTA
                ycursor_mod = ycursor_mod + 3
            end
        end
    elseif extra_point then
        ycursor_mod = ycursor_mod + 15
        color = COLOR_LIGHTRED

        if is_mouse_over then
            color = COLOR_RED
            ycursor_mod = ycursor_mod + 3
        end

    end
    return to_pen {
        ch = inshape and "X" or "o",
        fg = color,
        tile = dfhack.screen.findGraphicsTile(
            "CURSORS",
            direction[1],
            direction[2] + ycursor_mod
        ),
    }
end

function PenCache:get_point(point)
    return self:get_arr_fn()[point.x] and self:get_arr_fn()[point.x][point.y]
end

function PenCache:get_pen(point)
    point = Point(point)
    point.z = nil
    local n, w, e, s = false, false, false, false
    if self:get_point(point) then
        if point.y == 0 or not self:get_point(point - { y = 1 }) then n = true end
        if point.x == 0 or not self:get_point(point - { x = 1 }) then w = true end
        if not self:get_point(point + { x = 1 }) then e = true end
        if not self:get_point(point + { y = 1 }) then s = true end
    end

    local arr = self:get_arr_fn()

    local get_point = arr[point.x] and arr[point.x][point.y]
    -- Get the bit field to use as a key for the PENS map
    local pen_key = self:gen_pen_key(n, s, e, w, self.is_drag_pt_fn(point), point:is_mouse_over(), get_point,
        self.is_extra_pt_fn(point))


    -- Determine the cursor to use based on the input parameters
    local cursor = nil
    if pen_key and not self.pens[pen_key] then
        if get_point and not n and not w and not e and not s then cursor = self.cursors.INSIDE
        elseif get_point and n and w and not e and not s then cursor = self.cursors.NW
        elseif get_point and n and not w and not e and not s then cursor = self.cursors.NORTH
        elseif get_point and n and e and not w and not s then cursor = self.cursors.NE
        elseif get_point and not n and w and not e and not s then cursor = self.cursors.WEST
        elseif get_point and not n and not w and e and not s then cursor = self.cursors.EAST
        elseif get_point and not n and w and not e and s then cursor = self.cursors.SW
        elseif get_point and not n and not w and not e and s then cursor = self.cursors.SOUTH
        elseif get_point and not n and not w and e and s then cursor = self.cursors.SE
        elseif get_point and n and w and e and not s then cursor = self.cursors.N_NUB
        elseif get_point and n and not w and e and s then cursor = self.cursors.E_NUB
        elseif get_point and n and w and not e and s then cursor = self.cursors.W_NUB
        elseif get_point and not n and w and e and s then cursor = self.cursors.S_NUB
        elseif get_point and not n and w and e and not s then cursor = self.cursors.VERT_NS
        elseif get_point and n and not w and not e and s then cursor = self.cursors.VERT_EW
        elseif get_point and n and w and e and s then cursor = self.cursors.POINT
        elseif self.is_drag_pt_fn(point) and not get_point then cursor = self.cursors.INSIDE
        elseif self.is_extra_pt_fn(point) then cursor = self.cursors.INSIDE
        else cursor = nil
        end
    end

    if cursor then self.pens[pen_key] = self:make_pen(cursor, self.is_drag_pt_fn(point), point:is_mouse_over(), get_point
        , self.is_extra_pt_fn(point)) end

    return self.pens[pen_key]
end
