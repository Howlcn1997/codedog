import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import {
  claudeProjectKey,
  copyClaudeCodeChats,
} from "../electron/claude-sessions.mjs";
import { ProjectStore, exists } from "../electron/core.mjs";

async function fixture(t) {
  const directory = await fs.realpath(
    await fs.mkdtemp(path.join(os.tmpdir(), "codedog-claude-test-")),
  );
  t.after(() => fs.rm(directory, { recursive: true, force: true }));
  const configDirectory = path.join(directory, ".claude");
  const source = path.join(directory, "old", "demo-app");
  const target = path.join(directory, "new", "personal", "demo-app");
  const sourceDirectory = path.join(
    configDirectory,
    "projects",
    claudeProjectKey(source),
  );
  const targetDirectory = path.join(
    configDirectory,
    "projects",
    claudeProjectKey(target),
  );
  await fs.mkdir(sourceDirectory, { recursive: true });
  return {
    configDirectory,
    source,
    target,
    sourceDirectory,
    targetDirectory,
  };
}

test("Claude Code chats are copied to the new path without changing source history", async (t) => {
  const { configDirectory, source, target, sourceDirectory, targetDirectory } =
    await fixture(t);
  const sessionId = "11111111-1111-4111-8111-111111111111";
  const sourceChat = path.join(sourceDirectory, `${sessionId}.jsonl`);
  const original =
    JSON.stringify({ type: "user", cwd: source, message: "keep " + source }) +
    "\n" +
    JSON.stringify({ type: "assistant", cwd: path.join(source, "src") }) +
    "\n";
  await fs.writeFile(sourceChat, original);
  await fs.mkdir(path.join(sourceDirectory, sessionId));
  await fs.writeFile(
    path.join(sourceDirectory, sessionId, "tool-result.txt"),
    "historical output " + source,
  );
  await fs.writeFile(
    path.join(sourceDirectory, sessionId, "subagent.jsonl"),
    JSON.stringify({
      type: "user",
      cwd: path.join(source, "packages", "web"),
    }) + "\n",
  );
  await fs.writeFile(
    path.join(sourceDirectory, "sessions-index.json"),
    JSON.stringify({
      version: 1,
      originalPath: source,
      entries: [
        {
          sessionId,
          projectPath: source,
          fullPath: sourceChat,
          summary: "demo",
        },
      ],
    }),
  );

  const result = await copyClaudeCodeChats(source, target, configDirectory);
  assert.equal(result.copied, 1);
  assert.equal(result.skipped, 0);
  assert.equal(await fs.readFile(sourceChat, "utf8"), original);

  const copiedLines = (
    await fs.readFile(path.join(targetDirectory, `${sessionId}.jsonl`), "utf8")
  )
    .trim()
    .split("\n")
    .map(JSON.parse);
  assert.equal(copiedLines[0].cwd, target);
  assert.equal(copiedLines[1].cwd, path.join(target, "src"));
  assert.equal(copiedLines[0].message, "keep " + source);
  assert.equal(
    await fs.readFile(
      path.join(targetDirectory, sessionId, "tool-result.txt"),
      "utf8",
    ),
    "historical output " + source,
  );
  assert.equal(
    JSON.parse(
      await fs.readFile(
        path.join(targetDirectory, sessionId, "subagent.jsonl"),
        "utf8",
      ),
    ).cwd,
    path.join(target, "packages", "web"),
  );

  const index = JSON.parse(
    await fs.readFile(
      path.join(targetDirectory, "sessions-index.json"),
      "utf8",
    ),
  );
  assert.equal(index.originalPath, target);
  assert.equal(index.entries[0].projectPath, target);
  assert.equal(
    index.entries[0].fullPath,
    path.join(targetDirectory, `${sessionId}.jsonl`),
  );
});

test("existing target sessions are skipped instead of overwritten", async (t) => {
  const { configDirectory, source, target, sourceDirectory, targetDirectory } =
    await fixture(t);
  const sessionId = "22222222-2222-4222-8222-222222222222";
  await fs.writeFile(
    path.join(sourceDirectory, `${sessionId}.jsonl`),
    JSON.stringify({ cwd: source, value: "old" }) + "\n",
  );
  await fs.mkdir(targetDirectory, { recursive: true });
  const targetChat = path.join(targetDirectory, `${sessionId}.jsonl`);
  await fs.writeFile(
    targetChat,
    JSON.stringify({ cwd: target, value: "new" }) + "\n",
  );

  const result = await copyClaudeCodeChats(source, target, configDirectory);
  assert.equal(result.copied, 0);
  assert.equal(result.skipped, 1);
  assert.equal(JSON.parse(await fs.readFile(targetChat, "utf8")).value, "new");
});

test("a failed moved import removes its copied chats and restores the project", async (t) => {
  const { configDirectory, source, target, sourceDirectory, targetDirectory } =
    await fixture(t);
  const sessionId = "33333333-3333-4333-8333-333333333333";
  await fs.mkdir(source, { recursive: true });
  await fs.writeFile(path.join(source, "package.json"), "{}");
  await fs.writeFile(
    path.join(sourceDirectory, `${sessionId}.jsonl`),
    JSON.stringify({ cwd: source }) + "\n",
  );
  const root = path.dirname(path.dirname(target));
  await fs.mkdir(root, { recursive: true });
  const store = new ProjectStore(path.join(root, "codedog.json"));
  await store.init();
  await store.setRoot(root);
  store.save = async () => {
    throw Error("disk full");
  };
  const previousConfigDirectory = process.env.CLAUDE_CONFIG_DIR;
  process.env.CLAUDE_CONFIG_DIR = configDirectory;
  t.after(() => {
    if (previousConfigDirectory === undefined)
      delete process.env.CLAUDE_CONFIG_DIR;
    else process.env.CLAUDE_CONFIG_DIR = previousConfigDirectory;
  });

  await assert.rejects(
    store.importProject({
      name: path.basename(target),
      source,
      group: "personal",
      mode: "move",
      copyClaudeChats: true,
    }),
    /disk full/,
  );
  assert.equal(await exists(source), true);
  assert.equal(await exists(target), false);
  assert.equal(
    await exists(path.join(sourceDirectory, `${sessionId}.jsonl`)),
    true,
  );
  assert.equal(
    await exists(path.join(targetDirectory, `${sessionId}.jsonl`)),
    false,
  );
});
