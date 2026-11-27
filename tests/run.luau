--!strict
-- Runs every test: `luau tests/run.luau` from the repo root. Exits non-zero when a test fails.
-- Add each new spec file to the list below.

local t = require("./harness")

require("./view_model_spec")
require("./patch_spec")
require("./placement_spec")
require("./repo_root_spec")
require("./subagents_spec")
require("./subagent_strip_spec")
require("./subagent_reader_spec")
require("./pins_spec")
require("./needs_you_spec")
require("./row_chips_spec")
require("./effort_spec")
require("./recent_spec")
require("./recent_folders_spec")
require("./rename_spec")
require("./sessions_spec")
require("./turns_spec")
require("./tab_titles_spec")
require("./new_tab_spec")
require("./back_to_main_spec")
require("./viewing_spec")
require("./show_subagent_spec")
require("./state_colors_spec")
require("./live_zones_spec")
require("./copy_session_spec")

t.run()
