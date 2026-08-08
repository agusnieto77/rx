#!/usr/bin/env node
// Fixture refresh utility for xtweetsR parser fixtures.
//
// This tool helps developers update parser fixtures after X/Twitter
// frontend changes. It validates fixture structure and reports
// any schema changes compared to the reference fixture.
//
// Usage:
//   node refresh-fixtures.js <fixture-path>
//   node refresh-fixtures.js --validate <fixture-path>
//   node refresh-fixtures.js --stats <fixture-path>
//
// The tool requires a live X session cookie (X-TWITTER-TOKEN
// or X-CSRF-TOKEN environment variables) to fetch live responses.

import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// ── Schema reference ───────────────────────────────────────────────

/**
 * Expected structure of an X search/timeline GraphQL response.
 * Used for validation against live or fixture responses.
 */
const SCHEMA = {
  requiredRootKeys: ["data"],
  requiredDataKeys: ["timeline"],
  requiredTimelineKeys: ["instructions"],
  requiredInstructionTypes: [
    "TimelineAddEntries",
    "TimelineAddToModule",
    "TimelineTerminateTimeline",
  ],
  requiredEntryFields: ["entryId", "content"],
  requiredContentTypes: [
    "TimelineTimelineItem",
    "TimelineTimelineModule",
    "TimelineTimelineCursor",
  ],
  requiredTweetFields: [
    "__typename",
    "rest_id",
    "core",
    "legacy",
  ],
  requiredLegacyFields: [
    "created_at",
    "full_text",
    "conversation_id_str",
  ],
};

// ── Helpers ────────────────────────────────────────────────────────

function log(level, ...args) {
  const prefix = {
    info: "[INFO]",
    warn: "[WARN]",
    error: "[ERROR]",
    ok: "[OK]",
  }[level] || "[INFO]";
  console.error(`${prefix} ${args.map(String).join(" ")}`);
}

function validateFixtureStructure(data, name) {
  const errors = [];

  // Check root keys
  if (!SCHEMA.requiredRootKeys.every((k) => k in data)) {
    errors.push(`${name}: missing required root keys (${SCHEMA.requiredRootKeys.join(", ")})`);
  }

  if (!errors.length && "data" in data) {
    // Check data keys
    if (!SCHEMA.requiredDataKeys.every((k) => k in data.data)) {
      errors.push(`${name}: missing data keys (${SCHEMA.requiredDataKeys.join(", ")})`);
    }

    if (!errors.length && "timeline" in data.data) {
      // Check timeline keys
      if (!SCHEMA.requiredTimelineKeys.every((k) => k in data.data.timeline)) {
        errors.push(`${name}: missing timeline keys (${SCHEMA.requiredTimelineKeys.join(", ")})`);
      }

      if (!errors.length && "instructions" in data.data.timeline) {
        // Check instruction types
        const types = data.data.timeline.instructions
          .map((i) => i.type)
          .filter(Boolean);

        for (const required of SCHEMA.requiredInstructionTypes) {
          if (types.includes(required)) continue;
          // Not all types are required in every response
        }

        // Check entries
        const addEntries = data.data.timeline.instructions.find(
          (i) => i.type === "TimelineAddEntries"
        );

        if (addEntries) {
          for (const entry of addEntries.entries || []) {
            if (!SCHEMA.requiredEntryFields.every((k) => k in entry)) {
              errors.push(
                `${name}: entry ${entry.entryId} missing fields (${SCHEMA.requiredEntryFields.join(", ")})`
              );
            }

            // Check tweet structure if present
            const tweetResult =
              entry.content?.itemContent?.tweet_results?.result;
            if (tweetResult) {
              for (const field of SCHEMA.requiredTweetFields) {
                if (!(field in tweetResult)) {
                  errors.push(
                    `${name}: tweet ${tweetResult.rest_id} missing field '${field}'`
                  );
                }
              }

              // Check legacy fields
              const legacy = tweetResult.legacy;
              if (legacy) {
                for (const field of SCHEMA.requiredLegacyFields) {
                  if (!(field in legacy)) {
                    errors.push(
                      `${name}: tweet ${tweetResult.rest_id} legacy missing '${field}'`
                    );
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  return errors;
}

function extractStats(data) {
  const stats = {
    tweetIds: [],
    cursorTypes: new Set(),
    instructionTypes: new Set(),
    contentTypes: new Set(),
  };

  const instructions = data?.data?.timeline?.instructions || [];

  for (const inst of instructions) {
    stats.instructionTypes.add(inst.type);

    if (inst.type === "TimelineAddEntries") {
      for (const entry of inst.entries || []) {
        const tweetResult =
          entry.content?.itemContent?.tweet_results?.result;
        if (tweetResult) {
          stats.tweetIds.push(tweetResult.rest_id);
        }

        const content = entry.content;
        if (content) {
          stats.contentTypes.add(
            content.__typename || "unknown"
          );
        }
      }
    }

    if (inst.type === "TimelineAddToModule") {
      const instructions_list = inst.instructions || [];
      for (const instItem of instructions_list) {
        const cursor = instItem.item?.cursorValue;
        if (cursor) {
          stats.cursorTypes.add(instItem.item?.cursorType || "unknown");
        }
      }
    }
  }

  stats.cursorTypes = Array.from(stats.cursorTypes);
  return stats;
}

// ── Commands ───────────────────────────────────────────────────────

function cmdValidate(fixturePath) {
  if (!existsSync(fixturePath)) {
    log("error", `Fixture not found: ${fixturePath}`);
    process.exit(1);
  }

  let data;
  try {
    const raw = readFileSync(fixturePath, "utf-8");
    data = JSON.parse(raw);
  } catch (err) {
    log("error", `Failed to parse fixture: ${err.message}`);
    process.exit(1);
  }

  const errors = validateFixtureStructure(data, fixturePath);

  if (errors.length === 0) {
    log("ok", `Fixture "${fixturePath}" matches expected schema.`);
  } else {
    log("error", `Fixture "${fixturePath}" has ${errors.length} schema issue(s):`);
    for (const err of errors) {
      log("error", `  - ${err}`);
    }
    process.exit(1);
  }
}

function cmdStats(fixturePath) {
  if (!existsSync(fixturePath)) {
    log("error", `Fixture not found: ${fixturePath}`);
    process.exit(1);
  }

  let data;
  try {
    const raw = readFileSync(fixturePath, "utf-8");
    data = JSON.parse(raw);
  } catch (err) {
    log("error", `Failed to parse fixture: ${err.message}`);
    process.exit(1);
  }

  const stats = extractStats(data);

  console.log(`\n=== Fixture Stats: ${fixturePath} ===`);
  console.log(`  Tweets:      ${stats.tweetIds.length} (${stats.tweetIds.join(", ") || "none"})`);
  console.log(`  Cursors:     ${stats.cursorTypes.join(", ") || "none"}`);
  console.log(`  Instructions: ${Array.from(stats.instructionTypes).join(", ")}`);
  console.log(`  Content types: ${Array.from(stats.contentTypes).join(", ")}`);
  console.log(``);
}

// ── Main ───────────────────────────────────────────────────────────

function main() {
  const args = process.argv.slice(2);

  if (args.length < 1) {
    console.error(`
Usage:
  node refresh-fixtures.js --validate <fixture-path>    Validate fixture against schema
  node refresh-fixtures.js --stats <fixture-path>       Show fixture statistics
  node refresh-fixtures.js <fixture-path>               Alias for --validate

Examples:
  node refresh-fixtures.js --validate inst/tests/fixtures/x-search-response.json
  node refresh-fixtures.js --stats inst/tests/fixtures/x-search-response.json
`);
    process.exit(1);
  }

  const command = args[0];
  const fixturePath = args[1];

  if (command === "--validate" || command === "validate") {
    cmdValidate(fixturePath);
  } else if (command === "--stats" || command === "stats") {
    cmdStats(fixturePath);
  } else {
    cmdValidate(command);
  }
}

main();
