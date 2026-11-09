--!strict
-- The provider table: maps a model name to the omp provider id of its maker, whose logo Tern draws as the icon
-- `provider-<id>`. It names the maker, not the route: Claude through OpenRouter or Bedrock is still Anthropic.

local providers = {}

-- A model whose lower-case name holds `word` comes from `provider`; the first match wins.
local TABLE: { { word: string, provider: string } } = {
	{ word = "opus", provider = "anthropic" },
	{ word = "sonnet", provider = "anthropic" },
	{ word = "haiku", provider = "anthropic" },
	{ word = "claude", provider = "anthropic" },
	{ word = "gpt", provider = "openai" },
	{ word = "codex", provider = "openai" },
	{ word = "gemini", provider = "google" },
	{ word = "grok", provider = "xai" },
}

--- The provider id of `model`'s maker, or nil for a model the table does not know.
function providers.of(model: string): string?
	local lower = string.lower(model)
	for _, entry in TABLE do
		if string.find(lower, entry.word, 1, true) then
			return entry.provider
		end
	end
	return nil
end

return providers
