--!strict
-- What "Rename" on a live omp agent's row sends: the title the field starts with, and omp's `/rename <title>`
-- command for the title the user typed. Pure, so the plain `luau` CLI can test it.

local rename = {}

-- `text` trimmed, with every run of whitespace (a line break, a tab) written as one space; nil when blank.
local function oneLine(text: string?): string?
	if type(text) ~= "string" then
		return nil
	end
	local line = string.gsub(text, "%s+", " ")
	line = string.gsub(line, "^ ", "")
	line = string.gsub(line, " $", "")
	if line == "" then
		return nil
	end
	return line
end

--- The title the field starts with: the pane title omp set, without the icon character and space it puts in front.
function rename.current(paneTitle: string?): string?
	if type(paneTitle) ~= "string" then
		return nil
	end
	return oneLine(string.match(paneTitle, "^[\128-\255]+%s+(.*)$") or paneTitle)
end

--- omp's `/rename <title>` for the title the user typed; nil when the field was dismissed or left blank (a bare
--- `/rename` makes omp generate a title), or when the title is the current one.
function rename.command(typed: string?, current: string?): string?
	local title = oneLine(typed)
	if not title or title == current then
		return nil
	end
	return "/rename " .. title
end

return rename
