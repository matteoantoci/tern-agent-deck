--!strict
local t = require("./harness")
local providers = require("../lib/providers")

t.test("the provider table names the model maker", function()
	local cases: { { string } } = {
		{ "Opus 5.5", "anthropic" },
		{ "Sonnet 4.5", "anthropic" },
		{ "Haiku 4.5", "anthropic" },
		{ "claude-opus-4-1", "anthropic" },
		{ "GPT-5.1", "openai" },
		{ "gpt-5.1-codex-max", "openai" },
		{ "Codex Mini", "openai" },
		{ "Gemini 2.5 Pro", "google" },
		{ "Grok 4", "xai" },
	}
	for _, case in cases do
		t.eq(providers.of(case[1]), case[2], case[1])
	end
end)

t.test("an unknown model has no provider", function()
	t.eq(providers.of("Kimi K2"), nil)
	t.eq(providers.of(""), nil)
end)

return nil
