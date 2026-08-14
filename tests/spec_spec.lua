local Spec = require("trouble.spec")

describe("parses specs", function()
  it("parses a sort spec", function()
    local f1 = function() end
    ---@type ({input:trouble.Sort.spec, output:trouble.Sort})[]
    local tests = {
      {
        input = "foo",
        output = { { field = "foo" } },
      },
      {
        input = { "foo", "bar" },
        output = { { field = "foo" }, { field = "bar" } },
      },
      {
        input = { "foo", "-bar" },
        output = { { field = "foo" }, { field = "bar", desc = true } },
      },
      { input = f1, output = { { sorter = f1 } } },
      { input = { buf = 0 }, output = { { filter = { buf = 0 } } } },
      { input = { { buf = 0 } }, output = { { filter = { buf = 0 } } } },
      { input = { f1, "foo" }, output = { { sorter = f1 }, { field = "foo" } } },
    }

    for _, test in ipairs(tests) do
      assert.same(test.output, Spec.sort(test.input))
    end
  end)

  it("parses a section spec", function()
    local tests = {
      {
        input = {
          -- error from all files
          source = "diagnostics",
          filter = {
            severity = 1,
          },
          sort = { "filename", "-pos" },
        },
        output = {
          events = {},
          source = "diagnostics",
          sort = { { field = "filename" }, { field = "pos", desc = true } },
          filter = { severity = 1 },
          format = "{text}",
        },
      },
      {
        input = {
          source = "diagnostics",
          title = "Diagnostics",
          events = { "DiagnosticChanged", "BufEnter foo*" },
          format = "{message} {code}",
        },
        output = {
          source = "diagnostics",
          title = "Diagnostics",
          events = {
            { event = "DiagnosticChanged" },
            { event = "BufEnter", pattern = "foo*" },
          },
          format = "{message} {code}",
        },
      },
    }
    for _, test in ipairs(tests) do
      assert.same(test.output, Spec.section(test.input))
    end
  end)
end)
