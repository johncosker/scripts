-- Utilities for design.lua
--@ module = true

-- Point class used by gui/design
Point = defclass(Point)
Point.ATTRS{
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

function Point:__call(args)
end

function Point:__tostring()
    return "("..tostring(self.x)..", "..tostring(self.y)..", "..tostring(self.z)..")"
end
-- todo __concat for strings or tables or whatevers
function Point:get_add_sub_table(arg)
    local t_other = {x = 0, y = 0, z = 0}

    if type(arg) == "number" then
        t_other = Point{x =  arg, y = arg} -- As of now we don't want to add anything to z unless explicit
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
    return Point{x = self.x + t_other.x, y = self.y + t_other.y, z = self.z + t_other.z}
end

function Point:__sub(arg)
	local t_other = self:get_add_sub_table(arg)
    return Point{x = self.x - t_other.x, y = self.y - t_other.y, z = self.z - t_other.z}
end

-- For the purposes of GUI design, we only care about x and y being equal, z is only used for determining boundaries and x levels to apply the shape
function Point:__eq(other)
    self:check_valid(other)
    return self.x == other.x and self.y == other.y
end

-- Stack-like collection for points
Points = defclass(Points)
Points.ATTRS{
	points = DEFAULT_NIL
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
	local copy = Points{}
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

	error("Points class isn't meant to be modified.")
end
