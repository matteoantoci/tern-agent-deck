--!strict
-- The repo resolver: maps a working directory to the root of its main git repo, so that git worktrees and ovnfs
-- checkouts group under the repo they come from. It reads the file system only through the `Fs` it gets, so the
-- tests feed it fake paths; `resolver` caches every answer, because `tern.fs` calls run on the UI thread.
--
-- The rule, from the nearest folder `D` up from the working directory that holds a `.git` entry:
-- - `.git` is a directory: `D` is a main repo.
-- - `.git` is a file `gitdir: X` (a worktree, an ovnfs checkout, a submodule):
--   - `X/commondir` names the shared git dir `C` of a worktree; without it `C` is `X`.
--   - `C` is named `.git`: the main repo is the folder that holds `C`.
--   - `C/objects/info/alternates` borrows the objects of `<repo>/.git/objects` (an ovnfs checkout's private git
--     dir does): the main repo is `<repo>`.
--   - `X` has no `commondir` (a submodule, a `--separate-git-dir` repo): `D` is its own repo.
--   - Otherwise `C` is a bare repo, and it is the main repo.

local repoRoot = {}

--- The file-system calls the resolver makes. `read` returns nil for a missing file, a directory or a read error.
export type Fs = {
	exists: (path: string) -> boolean,
	read: (path: string) -> string?,
}

export type Resolver = {
	--- The main repo root of `cwd`, or nil when `cwd` is in no repo.
	of: (cwd: string?) -> string?,
}

local function trim(text: string): string
	return (string.match(text, "^%s*(.-)%s*$") :: string)
end

local function parent(path: string): string?
	if path == "/" then
		return nil
	end
	local up = string.match(path, "^(.*)/[^/]*$")
	if up == nil or up == "" then
		return "/"
	end
	return up
end

-- `path` without `.` and `..` segments and without a trailing slash; `path` must be absolute.
local function normalize(path: string): string
	local parts: { string } = {}
	for part in string.gmatch(path, "[^/]+") do
		if part == ".." then
			table.remove(parts)
		elseif part ~= "." then
			table.insert(parts, part)
		end
	end
	return "/" .. table.concat(parts, "/")
end

-- `target` read from a file in folder `base`: absolute as is, else relative to `base`.
local function resolve(base: string, target: string): string
	if string.sub(target, 1, 1) == "/" then
		return normalize(target)
	end
	return normalize(base .. "/" .. target)
end

local function firstLine(text: string?): string?
	if not text then
		return nil
	end
	local line = trim(string.match(text, "^[^\n]*") or "")
	if line == "" then
		return nil
	end
	return line
end

-- The main repo of the folder `dir`, whose `.git` entry exists.
local function mainRepo(fs: Fs, dir: string): string
	local pointer = fs.read(dir .. "/.git")
	local gitdir = pointer and string.match(pointer, "^gitdir:%s*(.-)%s*$")
	if not gitdir or gitdir == "" then
		return dir
	end
	local own = resolve(dir, gitdir)
	local commondir = firstLine(fs.read(own .. "/commondir"))
	local common = if commondir then resolve(own, commondir) else own
	if string.match(common, "/%.git$") then
		return parent(common) or dir
	end
	local alternate = firstLine(fs.read(common .. "/objects/info/alternates"))
	local borrowed = alternate and string.match(alternate, "^(/.+)/%.git/objects/?$")
	if borrowed then
		return normalize(borrowed)
	end
	if not commondir then
		return dir
	end
	return common
end

--- The main repo root of `cwd`, read from `fs` with no cache; nil when `cwd` is not absolute or in no repo.
function repoRoot.find(fs: Fs, cwd: string?): string?
	if type(cwd) ~= "string" or string.sub(cwd, 1, 1) ~= "/" then
		return nil
	end
	local dir: string? = normalize(cwd)
	while dir do
		local here = if dir == "/" then "" else dir
		if fs.exists(here .. "/.git") then
			return mainRepo(fs, if here == "" then "/" else here)
		end
		dir = parent(dir)
	end
	return nil
end

--- A resolver that looks each working directory up once and caches the answer, a miss included.
function repoRoot.resolver(fs: Fs): Resolver
	-- `false` marks a folder in no repo.
	local cache: { [string]: string | false } = {}
	return {
		of = function(cwd: string?): string?
			if type(cwd) ~= "string" then
				return nil
			end
			local known = cache[cwd]
			if known == nil then
				local found = repoRoot.find(fs, cwd)
				cache[cwd] = if found then found else false
				return found
			end
			if type(known) == "string" then
				return known
			end
			return nil
		end,
	}
end

return repoRoot
