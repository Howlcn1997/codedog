import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { executeCli } from "../electron/cli.mjs";
import { ProjectStore } from "../electron/core.mjs";

async function fixture(t) {
  const folder = await fs.realpath(
    await fs.mkdtemp(path.join(os.tmpdir(), "codedog-cli-")),
  );
  t.after(() => fs.rm(folder, { recursive: true, force: true }));
  const dataFile = path.join(folder, "data", "projects.json");
  const output = { stdout: "", stderr: "" };
  const options = {
    dataFile,
    cwd: folder,
    stdout: (text) => (output.stdout += text),
    stderr: (text) => (output.stderr += text),
  };
  return { folder, dataFile, output, options };
}

test("CLI adds external paths idempotently and path prints only the absolute path", async (t) => {
  const { folder, dataFile, output, options } = await fixture(t);
  const project = path.join(folder, "含 空格的项目");
  await fs.mkdir(project);
  assert.equal(await executeCli(["add", project], options), 0);
  output.stdout = "";
  assert.equal(await executeCli(["add", project], options), 0);
  assert.match(output.stdout, /项目已存在/);
  const store = new ProjectStore(dataFile);
  await store.init();
  await store.update(store.state.projects[0].id, { aliases: ["pay-api"] });
  output.stdout = "";
  assert.equal(await executeCli(["path", "pay-api"], options), 0);
  assert.equal(output.stdout, project + "\n");
  assert.equal(output.stderr, "");
});

test("ambiguous names print candidates and exact aliases open with the project IDE", async (t) => {
  const { folder, dataFile, output, options } = await fixture(t);
  const first = path.join(folder, "one", "service");
  const second = path.join(folder, "two", "service");
  await fs.mkdir(first, { recursive: true });
  await fs.mkdir(second, { recursive: true });
  const store = new ProjectStore(dataFile);
  await store.init();
  const a = (await store.add(first)).project;
  const b = (await store.add(second)).project;
  await store.update(b.id, { aliases: ["pay-api"], ide: "WebStorm" });
  assert.equal(await executeCli(["path", "service"], options), 1);
  assert.match(output.stderr, /找到多个候选项目/);
  output.stderr = "";
  const calls = [];
  assert.equal(
    await executeCli(["open", "pay-api"], {
      ...options,
      platform: "darwin",
      runCommand: async (...args) => calls.push(args),
    }),
    0,
  );
  assert.deepEqual(calls[0], ["open", ["-a", "WebStorm", second], second]);
  await assert.rejects(
    store.update(a.id, { aliases: ["PAY-API"] }),
    /已被项目/,
  );
});

test("separate store instances serialize writes without losing projects", async (t) => {
  const { folder, dataFile } = await fixture(t);
  const first = path.join(folder, "alpha");
  const second = path.join(folder, "beta");
  await Promise.all([fs.mkdir(first), fs.mkdir(second)]);
  const left = new ProjectStore(dataFile);
  const right = new ProjectStore(dataFile);
  await Promise.all([left.init(), right.init()]);
  await Promise.all([left.add(first), right.add(second)]);
  const check = new ProjectStore(dataFile);
  await check.init();
  assert.deepEqual(check.state.projects.map((project) => project.name).sort(), [
    "alpha",
    "beta",
  ]);
});

test("missing paths fail on stderr without contaminating stdout", async (t) => {
  const { folder, dataFile, output, options } = await fixture(t);
  const project = path.join(folder, "gone");
  await fs.mkdir(project);
  const store = new ProjectStore(dataFile);
  await store.init();
  await store.add(project);
  await fs.rm(project, { recursive: true });
  assert.equal(await executeCli(["path", "gone"], options), 1);
  assert.equal(output.stdout, "");
  assert.match(output.stderr, /项目路径已失效/);
});
