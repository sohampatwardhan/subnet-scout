// PreToolUse guard. Exit 2 blocks the write. Kiro's docs disagree on other
// non-zero codes, so this hook uses 2 when it means to block.
import { Buffer } from "node:buffer";

const chunks = [];
for await (const chunk of process.stdin) {
  chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
}

let event = {};
const raw = Buffer.concat(chunks).toString("utf8").trim();
if (raw) {
  try {
    event = JSON.parse(raw);
  } catch {
    process.exit(0);
  }
}

const input = event.tool_input ?? event.input ?? {};
const pathText = JSON.stringify(input.path ?? input.file_path ?? input.target_file ?? input.filePath ?? "");
const banned = /mcp\.json|[\\/]\.cursor[\\/]mcp|iconify-mcp/i.test(pathText);
if (banned) {
  console.error("Refusing to write MCP or Iconify server config into the repo.");
  process.exit(2);
}
process.exit(0);
