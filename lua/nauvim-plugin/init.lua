--- Host-side interfaces to the selected Nauvim client.
return {
  client = require("nauvim-plugin.client"),
  ["local-forward"] = require("nauvim-plugin.local-forward"),
  filesystem = require("nauvim-plugin.filesystem"),
  http = require("nauvim-plugin.http"),
  clipboard = require("nauvim-plugin.clipboard"),
}
