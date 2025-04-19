local ScriptEditorService = game:GetService("ScriptEditorService")

return function()
	local module = script["main"]
	local newModule = Instance.new("ModuleScript")

	ScriptEditorService:UpdateSourceAsync(newModule, function()
		return module.Source
	end)

	local success, response = pcall(require, newModule)
	return success, typeof(response) == "function" and response() or response
end
