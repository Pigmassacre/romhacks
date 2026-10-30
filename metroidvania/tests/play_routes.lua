-- The way through each stage, for tests/s_play.lua. Stairs are indices into
-- its STAIRS (Castlevania's table); "up" keeps jumping on the way there;
-- "hop" jumps straight up, then over, as far as the x given; "leap" is a running
-- jump, from the first x, in the air as far as the second.
return {
  [0] = {{"exit", "R"}},
  [1] = {{"stair", 7}, {"exit", "R"}},
  [2] = {{"go", 0x90}, {"stair", 5}, {"stair", 2}, {"stair", 7}, {"exit", "R"}},
  [3] = {{"boss", "R"}},
  [4] = {{"stair", 1}, {"stair", 3}, {"exit", "L"}},
  [5] = {{"stair", 1}, {"go", 0x1D4}, {"hop", "R"}, {"exit", "L"}},
  [6] = {{"stair", 1}, {"stair", 3}, {"boss", "L"}},
  [7] = {{"go", 0x3A}, {"hop", "R", 0x70}, {"stair", 1}, {"stair", 5}, {"go", 0x1B4}, {"hop", "R", 0x1EC}, {"go", 0x1F6}, {"hop", "R", 0x22C}, {"stair", 7}, {"exit", "R"}},
  [8] = {{"stair", 1}, {"stair", 3}, {"exit", "R"}},
  [9] = {{"boss", "R"}},
  [10] = {{"go", 0x278}, {"hop", "R", 0x296}, {"go", 0x2A4}, {"hop", "R", 0x2B4}, {"leap", 0x2D8, 0x2F6}, {"go", 0x5B8}, {"hop", "R", 0x5D8}, {"hop", "R", 0x5F0}, {"hop", "L", 0x5DC}, {"exit", "L"}},
  [11] = {{"exit", "R"}},
  [12] = {{"boss", "R"}},
  [13] = {{"stair", 3}, {"stair", 5}, {"stair", 1}, {"up", 0xB0}, {"stair", 8}, {"stair", 9}, {"exit", "R"}},
  [14] = {{"stair", 1}, {"stair", 3}, {"stair", 5}, {"stair", 7}, {"stair", 9}, {"stair", 11}, {"stair", 13}, {"stair", 15}, {"exit", "L"}},
  [15] = {{"stair", 1}, {"stair", 3}, {"boss", "L"}},
  [16] = {{"stair", 1}, {"exit", "L"}},
  [17] = {{"stair", 1}, {"stair", 3}, {"stair", 10}, {"stair", 12}, {"stair", 14}, {"stair", 16}, {"stair", 5}, {"stair", 8}, {"stair", 18}, {"exit", "L"}},
  [18] = {{"stair", 1}, {"boss", "L"}},
}
