--!strict
local t = require("./harness")
local repoRoot = require("../lib/repo_root")

-- A fake file system: each path maps to a file's text, or to `true` for a directory. It counts the lookups.
local function fakeFs(entries: { [string]: string | boolean })
	local fs = { calls = 0 }
	function fs.exists(path: string): boolean
		fs.calls += 1
		return entries[path] ~= nil
	end
	function fs.read(path: string): string?
		fs.calls += 1
		local entry = entries[path]
		if type(entry) == "string" then
			return entry
		end
		return nil
	end
	return fs
end

t.test("a folder inside a repo resolves to the repo's root", function()
	local fs = fakeFs({ ["/w/app/.git"] = true, ["/w/app/.git/HEAD"] = "ref: refs/heads/main\n" })
	t.eq(repoRoot.find(fs, "/w/app/src/lib"), "/w/app")
	t.eq(repoRoot.find(fs, "/w/app/"), "/w/app")
end)

t.test("a folder outside any repo has no root", function()
	t.eq(repoRoot.find(fakeFs({}), "/tmp/scratch"), nil)
	t.eq(repoRoot.find(fakeFs({}), nil), nil)
	t.eq(repoRoot.find(fakeFs({}), "relative/path"), nil)
end)

t.test("a git worktree resolves to its main repo", function()
	local fs = fakeFs({
		["/w/app/.git"] = true,
		["/w/app-wt/.git"] = "gitdir: /w/app/.git/worktrees/app-wt\n",
		["/w/app/.git/worktrees/app-wt/commondir"] = "../..\n",
	})
	t.eq(repoRoot.find(fs, "/w/app-wt/src"), "/w/app")
end)

t.test("a worktree with a relative gitdir resolves to its main repo", function()
	local fs = fakeFs({
		["/w/app/.git"] = true,
		["/w/app/trees/fix/.git"] = "gitdir: ../../.git/worktrees/fix",
		["/w/app/.git/worktrees/fix/commondir"] = "../..",
	})
	t.eq(repoRoot.find(fs, "/w/app/trees/fix"), "/w/app")
end)

t.test("an ovnfs checkout resolves to the repo whose objects its private git dir borrows", function()
	local fs = fakeFs({
		["/Users/me/checkouts/t04/.git"] = "gitdir: /Users/me/.local/state/ovnfs/git/t04\n",
		["/Users/me/.local/state/ovnfs/git/t04/objects/info/alternates"] = "/Users/me/Personal/tern-agents/.git/objects\n",
	})
	t.eq(repoRoot.find(fs, "/Users/me/checkouts/t04/lib"), "/Users/me/Personal/tern-agents")
end)

t.test("a submodule is its own repo", function()
	local fs = fakeFs({
		["/w/app/.git"] = true,
		["/w/app/vendor/lib/.git"] = "gitdir: ../../.git/modules/vendor/lib\n",
	})
	t.eq(repoRoot.find(fs, "/w/app/vendor/lib"), "/w/app/vendor/lib")
end)

t.test("a worktree of a bare repo resolves to the bare repo", function()
	local fs = fakeFs({
		["/w/app-wt/.git"] = "gitdir: /w/app.git/worktrees/app-wt",
		["/w/app.git/worktrees/app-wt/commondir"] = "../..",
	})
	t.eq(repoRoot.find(fs, "/w/app-wt"), "/w/app.git")
end)

t.test("the resolver looks a folder up once and answers again from its cache", function()
	local fs = fakeFs({ ["/w/app/.git"] = true })
	local resolver = repoRoot.resolver(fs)
	t.eq(resolver.of("/w/app/src"), "/w/app")
	t.eq(resolver.of("/tmp/scratch"), nil)
	local calls = fs.calls
	t.eq(resolver.of("/w/app/src"), "/w/app")
	t.eq(resolver.of("/tmp/scratch"), nil)
	t.eq(fs.calls, calls, "file-system calls after the first lookups")
end)

return nil
