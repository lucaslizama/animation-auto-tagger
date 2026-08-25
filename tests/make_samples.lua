-- Writes the sample frames and prints where they went, for the runners to
-- hand to Aseprite on the command line:
--
--   aseprite --batch --script tests/make_samples.lua
--   aseprite --batch --script-param base=orc --script tests/make_samples.lua
--
-- A trailing word would be read as a file to open, not as an argument, which is
-- why the character name comes through --script-param.
--
-- The drag-path suite needs the files to exist before Aseprite starts, since
-- Aseprite has to open them itself for the test to mean anything. That is why
-- this is a separate step rather than something the suite does for itself.

local here = (debug.getinfo(1, "S").source:sub(2)):match("^(.*)[/\\]") or "."
package.path = here .. "/?.lua;" .. package.path

local samples = require("samples")

local base = app.params and app.params["base"]
if base == "" then base = nil end

local dir, written = samples.ensure(nil, base)
print(("wrote %d of %d frames"):format(written, samples.frameCount()))
print("samples-dir: " .. dir)
