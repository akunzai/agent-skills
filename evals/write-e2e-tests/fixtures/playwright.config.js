const { defineConfig, devices } = require("@playwright/test");

module.exports = defineConfig({
  testDir: "e2e",
  use: {
    ...devices["Desktop Firefox"],
  },
});
