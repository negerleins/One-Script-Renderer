-- [Definitions]
local rawget = rawget
local pairs = pairs
local table_insert = table.insert
local setmetatable = setmetatable
local InstanceNew = Instance.new

-- [Cache]
local componentCache = setmetatable({}, { __mode = "kv" })
local elementCache = setmetatable({}, { __mode = "kv" })

-- [Memory]
local function monitorMemory(label, callback)
	local memBefore = gcinfo()
	print(label .. " - Memory before:", memBefore, "KB")

	callback()

	task.wait() -- Wait for next heartbeat to allow GC

	local memAfter = gcinfo()
	print(label .. " - Memory after:", memAfter, "KB")
	print(label .. " - Memory difference:", memBefore - memAfter, "KB")

	return memBefore - memAfter
end

-- [Types]
type StarterGuiType = StarterGui & {
	ScreenGui: ScreenGui,
}

type PlayersType = Players & {}

-- [Dependencies]
local Players = game:GetService("Players") :: PlayersType
local StarterGui = game:GetService("StarterGui") :: StarterGuiType
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

-- [Library]

local Thread = setmetatable({
	Tasks = {},
}, {
	__index = {
		new = function(self, func)
			local metadata = setmetatable({
				Thread = task.spawn(func),
			}, {
				__index = {
					kill = function(this)
						local success, response = pcall(task.cancel, this.Thread)
						if not success then
							warn(response)
						end
					end,
				},
			})

			table.insert(self.Tasks, metadata)
			return metadata
		end,
		clear = function(self)
			for index, task in ipairs(self.Tasks) do
				task:kill()
			end
		end,
	},
})

local RBXSignal = setmetatable({
	Connections = {},
}, {
	__newindex = function(self, name, signal)
		self:new(name, signal)
	end,
	__index = {
		new = function(self, name, signal)
			local metadata = setmetatable({
				Signal = signal,
			}, {
				__index = {
					kill = function(this)
						local success, response = pcall(function()
							this.Signal:Disconnect()
						end)

						if not success then
							warn(response)
						end
					end,
				},
			})

			self.Connections[name] = metadata
			return metadata
		end,
		clear = function(self)
			for index, signal in pairs(self.Connections) do
				signal:kill()
			end

			table.clear(self.Connections)
		end,
	},
})

local StyleSheet = setmetatable({
	Override = {
		["FlexList"] = { Name = "UIListLayout" },
		["FlexItem"] = { Name = "UIFlexItem" },
	},
}, {
	__index = {
		create = function(self, array)
			local result = {}

			for name, data in array do
				result[name] = setmetatable({
					data = data,
					parent = nil,
				}, {
					__index = {
						set = function(this)
							local data = this.data
							local parent = this.parent
							local Override = self.Override

							local overrideComponents = {}

							for __name, __value in pairs(data) do
								local override = Override[__name]

								if override then
									overrideComponents[override.Name] = overrideComponents[override.Name]
										or {
											name = override.Name,
											props = {},
										}
									for prop, value in pairs(__value) do
										overrideComponents[override.Name].props[prop] = value
									end
								end
							end

							for className, componentData in pairs(overrideComponents) do
								local object = this:gocl(parent, className)

								for prop, value in pairs(componentData.props) do
									if object[prop] ~= value then
										object[prop] = value
									end
								end
							end

							for __name, __value in pairs(data) do
								if not Override[__name] then
									if parent[__name] ~= __value then
										parent[__name] = __value
									end
								end
							end
						end,
						gocl = function(_, parent, className)
							local parentCache = componentCache[parent]
							if not parentCache then
								parentCache = {}
								componentCache[parent] = parentCache
							end

							local object = parentCache[className]
							if not object then
								object = parent:FindFirstChildOfClass(className)
								if not object then
									object = InstanceNew(className, parent)
								end
								parentCache[className] = object
							end

							return object
						end,
					},
				})
			end

			return result
		end,
	},
	__metatable = "locked",
})

local Element = setmetatable({}, {
	__index = {
		new = function(class, properties, children)
			local success, output = pcall(Instance.new, class)
			assert(success, `[{class}] is not an valid object class`)

			local element = setmetatable({
				Properties = properties,
				Children = children,
				Object = output,
				Id = HttpService:GenerateGUID(false),
				Attributes = {},
			}, {
				__index = {
					remove = function(self)
						if self.Children then
							for _, child in pairs(self.Children) do
								if typeof(child) == "table" and child.cleanup then
									child:cleanup()
								end
							end

							self.Children = nil
						end

						self.Properties = nil

						if self.Object and self.Object:IsA("Instance") then
							self.Object:Destroy()
							self.Object = nil
						end
					end,
					draggable = function(self, ObjectPosition, MousePosition)
						if self.Attributes["StartPosition"] then
							self.Attributes["StartPosition"] = nil
						elseif ObjectPosition then
							self.Attributes["StartPosition"] = ObjectPosition
						else
							self.Attributes["StartPosition"] = nil
						end

						if self.Attributes["StartMousePosition"] then
							self.Attributes["StartMousePosition"] = nil
						elseif MousePosition then
							self.Attributes["StartMousePosition"] = MousePosition
						else
							self.Attributes["StartMousePosition"] = nil
						end

						if self.Attributes["StartPosition"] and self.Attributes["StartMousePosition"] then
							self.Attributes["Drag"] = true
						else
							self.Attributes["Drag"] = false
						end
					end,
				},
				__metatable = "locked",
			})

			elementCache[element.Id] = element
			return element
		end,
	},
	__metatable = "locked",
})

local Render = setmetatable({
	ScreenGui = Instance.new("ScreenGui"),
	Location = nil,
	Style = nil,
	Children = nil,
	Classes = {},
	RBXSignal = RBXSignal,
	Player = Players.LocalPlayer,
}, {
	__index = {
		screen = function(self, children)
			assert(rawget(self, "Location"), "Location was not specified for render.")
			self.ScreenGui.Parent = self.Location

			self.Children = children
			self:update()
		end,
		update = function(self)
			assert(rawget(self, "Children"), "Children where not set for render.")

			if self.Style then
				self.Style.parent = self.ScreenGui
				self.Style:set()
			end

			local stack = { { elements = self.Children, parent = self.ScreenGui } }
			local current

			while #stack > 0 do
				current = table.remove(stack)

				for _, element in pairs(current.elements) do
					local obj = element.Object

					if obj.Parent ~= current.parent then
						obj.Parent = current.parent
					end

					local props = rawget(element, "Properties")
					if props then
						local style = rawget(props, "Style")
						local className = rawget(props, "ClassName")
						local onPress = rawget(props, "OnPress")
						local onRelease = rawget(props, "OnRelease")
						local onHover = rawget(props, "OnHover")
						local onDrag = rawget(props, "OnDrag")
						local onMoved = rawget(props, "OnMoved")
						local onHeartbeat = rawget(props, "OnHeartbeat")

						local hasText = rawget(props, "Text")

						if style then
							style.parent = obj
							style:set()
						end

						if className then
							rawset(self.Classes, className, element)
						end

						if hasText and obj["Text"] then
							obj.Text = hasText
						end

						if onMoved then
							local Context = `{element.Id}:OnMoved`

							if not self.RBXSignal.Connections[Context] then
								self.RBXSignal[Context] = obj.MouseMoved:Connect(function(...)
									onMoved(element, ...)
								end)
							end
						end

						if onRelease and table.find({ "TextButton", "ImageButton" }, obj.ClassName) then
							local Context = `{element.Id}:onRelease`

							if not self.RBXSignal.Connections[Context] then
								self.RBXSignal[Context] = obj.MouseButton1Up:Connect(function(...)
									onRelease(element, ...)
								end)
							end
						end

						if onPress and table.find({ "TextButton", "ImageButton" }, obj.ClassName) then
							local Context = `{element.Id}:OnPress`

							if not self.RBXSignal.Connections[Context] then
								self.RBXSignal[Context] = obj.MouseButton1Down:Connect(function(...)
									onPress(element, ...)
								end)
							end
						end

						if onHeartbeat then
							local Context = `{element.Id}:OnHeartbeat`

							if not self.RBXSignal.Connections[Context] then
								self.RBXSignal[Context] = RunService.Heartbeat:Connect(function(...)
									onHeartbeat(element, ...)
								end)
							end
						end

						if onDrag then
							local Context = `{element.Id}:OnDrag`

							if not self.RBXSignal.Connections[Context] then
								self.RBXSignal[Context] = RunService.RenderStepped:Connect(function()
									local StartPosition = rawget(element.Attributes, "StartPosition")
									local StartMousePosition = rawget(element.Attributes, "StartMousePosition")
									local MousePosition = rawget(element.Attributes, "MousePosition")

									if rawget(element.Attributes, "Drag") and StartPosition and MousePosition then
										local __delta = Vector2.new(MousePosition.X, MousePosition.Y) - StartMousePosition

										onDrag(
											element,
											UDim2.new(
												StartPosition.X.Scale,
												StartPosition.X.Offset + __delta.X,
												StartPosition.Y.Scale,
												StartPosition.Y.Offset + __delta.Y
											)
										)
									end
								end)
							end
						end

						if onHover then
							local MouseEnterContext = `{element.Id}:MouseEnter`

							if not self.RBXSignal.Connections[MouseEnterContext] then
								self.RBXSignal[MouseEnterContext] = obj.MouseEnter:Connect(function(X, Y)
									local frameX = obj.AbsolutePosition.X
									local frameY = obj.AbsolutePosition.Y

									local relativeX = X - frameX
									local relativeY = Y - frameY
									onHover(element, true, relativeX, relativeY)
								end)
							end

							local MouseLeaveContext = `{element.Id}:MouseLeave`

							if not self.RBXSignal.Connections[MouseLeaveContext] then
								self.RBXSignal[MouseLeaveContext] = obj.MouseLeave:Connect(function()
									onHover(element, false)
								end)
							end
						end
					end

					local __children = rawget(element, "Children")
					if __children then
						table_insert(stack, {
							elements = __children,
							parent = obj,
						})
					end
				end
			end
		end,
		class = function(self, name)
			return rawget(self.Classes, name) or nil
		end,
		destroy = function(self)
			self.RBXSignal:clear()

			if self.Children then
				for _, element in pairs(self.Children) do
					if element.cleanup then
						element:cleanup()
					end
				end
			end

			table.clear(self.Classes)

			if self.ScreenGui then
				self.ScreenGui:Destroy()
				self.ScreenGui = nil
			end

			self.Children = nil
			self.Style = nil

			for parent, cache in pairs(componentCache) do
				table.clear(cache)
			end

			for parent, cache in pairs(elementCache) do
				table.clear(cache)
			end

			table.clear(componentCache)
			table.clear(elementCache)
		end,
	},
	__metatable = "locked",
})

-- [Style]
local styles = StyleSheet:create({
	["Screen"] = {
		ResetOnSpawn = false,
	},
	["Main"] = {
		FlexList = {
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		},
		Size = UDim2.fromOffset(200, 500),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 0.8,
	},
	["Button"] = {
		Size = UDim2.fromOffset(200, 50),
		ClipsDescendants = true,
		AutoButtonColor = false,
		BackgroundColor3 = Color3.fromRGB(255, 117, 117),
	},
	["Button:OnHover"] = {
		BackgroundColor3 = Color3.fromRGB(167, 90, 90),
	},
	["Button:OnPress"] = {
		BackgroundColor3 = Color3.fromRGB(172, 79, 79),
	},
})

Render.Location = RunService:IsRunning() and Players.LocalPlayer.PlayerGui or StarterGui
Render.Style = styles.Screen

return function()
	-- [Functions]
	local function createSplashEffect(parent, x, y)
		local splash = Instance.new("Frame")
		splash.Size = UDim2.fromOffset(0, 0)
		splash.Position = UDim2.fromOffset(x, y)
		splash.BackgroundColor3 = Color3.fromRGB(94, 40, 40)
		splash.BackgroundTransparency = 0.3
		splash.AnchorPoint = Vector2.new(0.5, 0.5)

		local uiCorner = Instance.new("UICorner")
		uiCorner.CornerRadius = UDim.new(1, 0)
		uiCorner.Parent = splash

		splash.Parent = parent

		local parentWidth = parent.AbsoluteSize.X
		local parentHeight = parent.AbsoluteSize.Y

		local distToTopLeft = math.sqrt(x ^ 2 + y ^ 2)
		local distToTopRight = math.sqrt((parentWidth - x) ^ 2 + y ^ 2)
		local distToBottomLeft = math.sqrt(x ^ 2 + (parentHeight - y) ^ 2)
		local distToBottomRight = math.sqrt((parentWidth - x) ^ 2 + (parentHeight - y) ^ 2)

		local maxDistance = math.max(distToTopLeft, distToTopRight, distToBottomLeft, distToBottomRight)
		local maxSize = maxDistance * 2

		local tweenInfo = TweenInfo.new(
			0.6, -- Duration
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		)

		local tween = game:GetService("TweenService"):Create(splash, tweenInfo, {
			Size = UDim2.fromOffset(maxSize, maxSize),
			Position = UDim2.new(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
		})

		tween:Play()

		tween.Completed:Connect(function()
			splash:Destroy()
		end)

		return splash
	end

	-- [Render]
	Render:screen({
		["Main"] = Element.new("Frame", {
			Style = styles.Main,
			ClassName = "MainFrame",
			OnDrag = function(self, position)
				self.Properties.Style.data.Position = position
			end,
		}, {
			["Button"] = Element.new("TextButton", {
				Style = styles.Button,
				ClassName = "Button",
				Text = "0",
				OnPress = function(self)
					monitorMemory("Render Destroy", function()
						Render:destroy()
					end)
				end,
				OnHover = function(self, isHovering, x, y)
					if isHovering then
						self.Properties.Style = styles["Button:OnHover"]
						createSplashEffect(Render:class("Button").Object, x, y)
					else
						self.Properties.Style = styles["Button"]
					end
				end,
				OnHeartbeat = function(self, ...)
					local __number = tonumber(self.Properties.Text)
					self.Properties.Text = (__number + 1)
				end,
			}),
			["ButtonDragger"] = Element.new("TextButton", {
				Style = styles.Button,
				ClassName = "ButtonDragger",
				Text = "Drag Me",
				OnPress = function(self, x, y)
					self.Properties.Style = styles["Button:OnPress"]

					local class = Render:class("MainFrame")
					class:draggable(class.Object.Position, Vector2.new(x, y))
				end,
				OnRelease = function(self)
					self.Properties.Style = styles["Button"]

					local class = Render:class("MainFrame")
					class:draggable()
				end,
				OnHover = function(self, isHovering, x, y)
					if not isHovering then
						self.Properties.Style = styles["Button"]

						local class = Render:class("MainFrame")
						class:draggable()
					else
						self.Properties.Style = styles["Button:OnHover"]
						createSplashEffect(Render:class("ButtonDragger").Object, x, y)
					end
				end,
				OnMoved = function(self, x, y)
					Render:class("MainFrame").Attributes["MousePosition"] = Vector2.new(x, y)
				end
			}),
		}),
	})

	Render.RBXSignal.UpdateHeartBeat = RunService.Heartbeat:Connect(function()
		Render:update()
	end)
end
