import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import {
  ProjectStore,
  inspect,
  diskUsage,
  exists,
  within,
  safeName,
  run,
  installPlan,
  dependencyCleanupPlan,
  cleanProjectDependencies,
} from "../electron/core.mjs";
async function fixture(t) {
  const dir = await fs.realpath(
    await fs.mkdtemp(path.join(os.tmpdir(), "codedog-test-")),
  );
  t.after(() => fs.rm(dir, { recursive: true, force: true }));
  const root = path.join(dir, "projects"),
    source = path.join(dir, "source");
  await fs.mkdir(root);
  await fs.mkdir(source);
  await fs.writeFile(
    path.join(source, "package.json"),
    JSON.stringify({
      name: "demo",
      dependencies: { react: "^19" },
      devDependencies: { typescript: "^5" },
      engines: { node: ">=22" },
    }),
  );
  const store = new ProjectStore(path.join(dir, "data.json"));
  await store.init();
  await store.setRoot(root);
  return { dir, root, source, store };
}
test("copy import, dependency inspection, metadata persistence and non-destructive removal", async (t) => {
  const { store, source, root, dir } = await fixture(t);
  const p = await store.importProject({
    name: "hello",
    source,
    group: "personal",
    mode: "copy",
  });
  assert.equal(p.path, path.join(root, "personal", "hello"));
  assert.ok(await exists(source));
  const info = await inspect(p.path);
  assert.deepEqual(info.stacks, ["Node.js"]);
  assert.equal(info.dependencyState, "pending");
  assert.equal(info.dependencies.length, 2);
  await store.update(p.id, {
    favorite: true,
    tags: ["front"],
    notes: "memo",
    archived: true,
  });
  const fresh = new ProjectStore(path.join(dir, "data.json"));
  await fresh.init();
  assert.equal(fresh.state.projects[0].notes, "memo");
  assert.equal(fresh.state.projects[0].archived, true);
  await fresh.forget(p.id);
  assert.ok(await exists(p.path));
  assert.equal(fresh.state.projects.length, 0);
});
test("search aliases and saved launcher filters are normalized and persisted", async (t) => {
  const { store, source, dir } = await fixture(t);
  const project = await store.importProject({
    name: "gateway",
    source,
    group: "company",
    mode: "copy",
  });
  await store.update(project.id, {
    aliases: [" 网关 ", "gateway-api", "网关"],
  });
  await store.setSavedFilters([
    {
      id: "backend",
      name: " 公司后端 ",
      query: "api",
      group: "company",
      stack: "Go",
      tag: "后端",
      sort: "unexpected",
    },
  ]);
  const fresh = new ProjectStore(path.join(dir, "data.json"));
  await fresh.init();
  assert.deepEqual(fresh.state.projects[0].aliases, ["网关", "gateway-api"]);
  assert.deepEqual(fresh.state.savedFilters[0], {
    id: "backend",
    name: "公司后端",
    query: "api",
    group: "company",
    stack: "Go",
    tag: "后端",
    sort: "recent",
  });
  await assert.rejects(
    store.setSavedFilters([{ name: "", id: "bad" }]),
    /筛选名称/,
  );
});
test("move and register enforce root containment; duplicates cannot overwrite", async (t) => {
  const { store, source, root } = await fixture(t);
  await assert.rejects(
    store.importProject({
      name: "test",
      source,
      group: "company",
      mode: "register",
    }),
    /根目录/,
  );
  const p = await store.importProject({
    name: "hello",
    source,
    group: "company",
    mode: "move",
  });
  assert.equal(await exists(source), false);
  await assert.rejects(
    store.importProject({
      name: "hello",
      source: p.path,
      group: "company",
      mode: "copy",
    }),
    /已存在/,
  );
  await assert.rejects(
    store.importProject({
      name: "hello",
      source: p.path,
      group: "company",
      mode: "register",
    }),
    /管理中/,
  );
  await assert.rejects(store.setRoot(path.dirname(root)), /已有项目/);
});
test("reject path traversal, root self-copy, invalid clone protocol and symlink escape", async (t) => {
  const { store, source, root, dir } = await fixture(t);
  for (const name of ["../bad", "/tmp/bad", "..", "x/y", "-bad"])
    assert.throws(() => safeName(name));
  assert.equal(within("/a/b", "/a/bad"), false);
  await assert.rejects(
    store.importProject({
      name: "loop",
      source: dir,
      group: "personal",
      mode: "copy",
    }),
    /导入自身/,
  );
  await assert.rejects(
    store.importProject({
      name: "bad",
      url: "file:///tmp/repo",
      group: "personal",
      mode: "clone",
    }),
    /HTTPS/,
  );
  await fs.symlink(source, path.join(root, "company"));
  await assert.rejects(
    store.importProject({
      name: "bad",
      source,
      group: "company",
      mode: "copy",
    }),
    /根目录之外/,
  );
});
test("Go and Python are recognized without reporting shared Go cache as installed", async (t) => {
  const { source } = await fixture(t);
  await fs.writeFile(
    path.join(source, "go.mod"),
    "module test.dev/app\n\ngo 1.24\nrequire (\n example.org/pkg v1.2.3\n)\n",
  );
  await fs.writeFile(
    path.join(source, "pyproject.toml"),
    '[project]\nrequires-python = ">=3.12"\ndependencies = ["httpx>=0.28", "fastapi"]\n',
  );
  await fs.writeFile(path.join(source, "uv.lock"), "");
  const info = await inspect(source);
  assert.deepEqual(info.stacks, ["Node.js", "Go", "Python"]);
  assert.equal(info.environments[1].installed, null);
  assert.equal(info.environments[2].manager, "uv");
  assert.ok(info.dependencies.some((d) => d.name === "example.org/pkg"));
  assert.ok(info.dependencies.some((d) => d.name === "fastapi"));
});
test("scan skips dependencies; disk usage separates project-local dependencies", async (t) => {
  const { store, root } = await fixture(t);
  await fs.mkdir(path.join(root, "x", "node_modules", "fake"), {
    recursive: true,
  });
  await fs.writeFile(path.join(root, "x", "package.json"), "{}");
  await fs.writeFile(
    path.join(root, "x", "node_modules", "fake", "package.json"),
    "{}",
  );
  const found = await store.scan(root);
  assert.deepEqual(found, [path.join(root, "x")]);
  const usage = await diskUsage(path.join(root, "x"));
  assert.equal(usage.source, 2);
  assert.equal(usage.dependencies, 2);
});
test("concurrent imports are serialized and invalid manifests show meaningful errors", async (t) => {
  const { store, source } = await fixture(t);
  const input = { name: "same", source, mode: "copy", group: "personal" };
  const outcomes = await Promise.allSettled([
    store.importProject(input),
    store.importProject(input),
  ]);
  assert.equal(outcomes.filter((x) => x.status === "fulfilled").length, 1);
  assert.equal(store.state.projects.length, 1);
  await fs.writeFile(path.join(source, "package.json"), "{broken");
  await assert.rejects(inspect(source), /无法解析/);
});
test("commands preserve arguments and Python installs remain in the project virtualenv", async (t) => {
  const { source } = await fixture(t);
  const output = await run(
    process.execPath,
    ["-e", "console.log(process.argv[1])", "hello;$(whoami)"],
    source,
  );
  assert.equal(output, "hello;$(whoami)");
  const plan = installPlan(
    { stack: "Python", manager: "pip", manifest: "requirements.txt" },
    source,
  );
  assert.ok(plan[1].command.startsWith(source));
  assert.deepEqual(plan[1].args, [
    "-m",
    "pip",
    "install",
    "-r",
    "requirements.txt",
  ]);
});
test("failed persistence rolls a moved folder back to its original location", async (t) => {
  const { store, source, root } = await fixture(t);
  store.save = async () => {
    throw Error("disk full");
  };
  await assert.rejects(
    store.importProject({
      name: "rollback",
      source,
      mode: "move",
      group: "personal",
    }),
    /disk full/,
  );
  assert.ok(await exists(source));
  assert.equal(await exists(path.join(root, "personal", "rollback")), false);
  assert.equal(store.state.projects.length, 0);
});
test("an indexed folder replaced by an external symlink cannot be opened or inspected", async (t) => {
  const { store, source, dir } = await fixture(t);
  const p = await store.importProject({
    name: "linked",
    source,
    mode: "copy",
    group: "personal",
  });
  await fs.rm(p.path, { recursive: true });
  await fs.symlink(source, p.path);
  await assert.rejects(store.get(p.id), /移出根目录/);
  const list = await store.list();
  assert.ok(list[0].error.includes("移出根目录"));
  assert.deepEqual(list[0].dependencies, []);
});

test("batch imports share selected tags, normalize duplicates and retain them after restart", async (t) => {
  const { store, source, dir } = await fixture(t);
  for (const name of ["batch-one", "batch-two"]) {
    await store.importProject({
      name,
      source,
      mode: "copy",
      group: "company",
      tags: [" 工作 ", "新标签", "工作", ""],
    });
  }
  const reopened = new ProjectStore(path.join(dir, "data.json"));
  await reopened.init();
  assert.equal(reopened.state.projects.length, 2);
  for (const project of reopened.state.projects)
    assert.deepEqual(project.tags, ["工作", "新标签"]);
  const legacy = await reopened.importProject({
    name: "without-tags",
    source,
    mode: "copy",
    group: "personal",
  });
  assert.deepEqual(legacy.tags, []);
});

test("invalid import tags are rejected before moving project files", async (t) => {
  const { store, source, root } = await fixture(t);
  for (const tags of [
    "not-an-array",
    [42],
    ["x".repeat(41)],
    Array.from({ length: 21 }, (_, i) => `tag-${i}`),
  ]) {
    await assert.rejects(
      store.importProject({
        name: "invalid-tags",
        source,
        mode: "move",
        group: "personal",
        tags,
      }),
      /标签/,
    );
    assert.ok(await exists(source));
    assert.equal(
      await exists(path.join(root, "personal", "invalid-tags")),
      false,
    );
  }
});

test("copy import never passes an existing destination to cp, including nested and hidden files", async (t) => {
  const { store, source, root } = await fixture(t);
  await fs.mkdir(path.join(source, "nested", "empty"), { recursive: true });
  await fs.writeFile(path.join(source, "nested", "data.txt"), "keep me");
  await fs.writeFile(path.join(source, ".hidden"), "hidden");
  await fs.symlink("nested/data.txt", path.join(source, "link"));
  const original = fs.cp;
  t.mock.method(fs, "cp", async (from, to, options) => {
    assert.equal(
      await exists(to),
      false,
      "cp destination must not already exist",
    );
    return original(from, to, options);
  });
  const p = await store.importProject({
    name: "strict-copy",
    source,
    group: "company",
    mode: "copy",
  });
  assert.equal(
    await fs.readFile(path.join(p.path, "nested", "data.txt"), "utf8"),
    "keep me",
  );
  assert.equal(
    await fs.readFile(path.join(p.path, ".hidden"), "utf8"),
    "hidden",
  );
  assert.ok(await exists(path.join(p.path, "nested", "empty")));
  assert.equal(await fs.readlink(path.join(p.path, "link")), "nested/data.txt");
});

test("failed partial copy cleans only its own destination and can be retried", async (t) => {
  const { store, source, root } = await fixture(t);
  await fs.writeFile(path.join(source, "second.txt"), "untouched");
  const original = fs.cp;
  let count = 0;
  const mock = t.mock.method(fs, "cp", async (...args) => {
    if (++count === 2)
      throw Object.assign(new Error("simulated EEXIST"), { code: "EEXIST" });
    return original(...args);
  });
  const input = { name: "retry-copy", source, group: "company", mode: "copy" };
  await assert.rejects(store.importProject(input), /EEXIST/);
  assert.equal(await exists(path.join(root, "company", "retry-copy")), false);
  assert.equal(
    await fs.readFile(path.join(source, "second.txt"), "utf8"),
    "untouched",
  );
  assert.equal(store.state.projects.length, 0);
  mock.mock.restore();
  await store.importProject(input);
  assert.equal(store.state.projects.length, 1);
});

test("UI mode persists across restarts without changing project records", async (t) => {
  const { store, source, dir } = await fixture(t);
  await store.importProject({
    name: "mode-project",
    source,
    group: "personal",
    mode: "copy",
  });
  await store.setMode("compact");
  const reopened = new ProjectStore(path.join(dir, "data.json"));
  await reopened.init();
  assert.equal(reopened.state.uiMode, "compact");
  assert.equal(reopened.state.projects[0].name, "mode-project");
  await reopened.setMode("standard");
  await assert.rejects(reopened.setMode("invalid"), /无效的界面模式/);
  assert.equal(reopened.state.uiMode, "standard");
});

test("default terminal preference persists and rejects unknown applications", async (t) => {
  const { store, dir } = await fixture(t);
  assert.equal(store.state.terminal || "system", "system");
  await store.setTerminal("warp");
  const reopened = new ProjectStore(path.join(dir, "data.json"));
  await reopened.init();
  assert.equal(reopened.state.terminal, "warp");
  await assert.rejects(reopened.setTerminal("/tmp/custom-command"), /不支持/);
  assert.equal(reopened.state.terminal, "warp");
  await reopened.setTerminal("system");
  assert.equal(reopened.state.terminal, "system");
});
test("theme preference persists, validates values and rolls back failed saves", async (t) => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "codedog-theme-"));
  t.after(() => fs.rm(dir, { recursive: true, force: true }));
  const file = path.join(dir, "state.json");
  const store = new ProjectStore(file);
  for (const theme of ["dark", "light", "system"]) {
    await store.setTheme(theme);
    const restored = new ProjectStore(file);
    await restored.init();
    assert.equal(restored.state.theme, theme);
  }
  await assert.rejects(store.setTheme("unknown"), /无效/);
  store.save = async () => {
    throw Error("disk full");
  };
  await assert.rejects(store.setTheme("dark"), /disk full/);
  assert.equal(store.state.theme, "system");
});
test("custom groups persist and work for importing and reclassifying projects", async (t) => {
  const { store, source, root } = await fixture(t);
  const group = await store.createGroup("  开源工具  ");
  assert.equal(group.name, "开源工具");
  assert.match(group.id, /^group-[a-f0-9-]+$/);
  const p = await store.importProject({
    name: "custom",
    source,
    mode: "copy",
    group: group.id,
  });
  assert.equal(p.group, group.id);
  assert.equal(p.path, path.join(root, "开源工具", "custom"));
  await store.update(p.id, { group: "company" });
  await store.update(p.id, { group: group.id });
  const restored = new ProjectStore(store.file);
  await restored.init();
  assert.equal(restored.groups()[group.id], "开源工具");
  assert.equal(restored.state.projects[0].group, group.id);
  assert.equal(restored.groups().personal, "个人项目");
  await assert.rejects(store.createGroup("开源工具"), /同名/);
  await assert.rejects(store.createGroup("公司项目"), /同名/);
  await assert.rejects(store.createGroup("  "), /1–40/);
  await assert.rejects(store.update(p.id, { group: "../escape" }), /无效/);
  await assert.rejects(
    store.importProject({
      name: "bad",
      source,
      mode: "copy",
      group: "__proto__",
    }),
    /无效/,
  );
});
test("group creation serializes duplicate checks and rolls back failed writes", async (t) => {
  const { store } = await fixture(t);
  const results = await Promise.allSettled([
    store.createGroup("Tools"),
    store.createGroup("tools"),
  ]);
  assert.equal(results.filter((r) => r.status === "fulfilled").length, 1);
  const previous = [...store.state.groups];
  store.save = async () => {
    throw Error("disk full");
  };
  await assert.rejects(store.createGroup("Other"), /disk full/);
  assert.deepEqual(store.state.groups, previous);
});

test("custom group folders use names while legacy project paths remain usable", async (t) => {
  const { store, source, root } = await fixture(t);
  const group = await store.createGroup("Github");
  const legacyPath = path.join(root, group.id, "old");
  await fs.mkdir(legacyPath, { recursive: true });
  const old = await store.importProject({
    name: "old",
    source: legacyPath,
    group: group.id,
    mode: "register",
  });
  const fresh = await store.importProject({
    name: "fresh",
    source,
    group: group.id,
    mode: "copy",
  });
  assert.equal(fresh.path, path.join(root, "Github", "fresh"));
  assert.equal((await store.get(old.id)).path, legacyPath);
  await assert.rejects(
    store.importProject({
      name: "fresh",
      source,
      group: group.id,
      mode: "copy",
    }),
    /已存在/,
  );
  for (const name of [
    "../outside",
    "/absolute",
    "folder/name",
    "a\\b",
    "CON",
    "Company",
    "trailing.",
  ])
    await assert.rejects(store.createGroup(name), /文件夹名称/);
});

test("dependency cleanup removes only project-local dependency directories", async (t) => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "codedog-cleanup-"));
  t.after(() => fs.rm(dir, { recursive: true, force: true }));
  const project = path.join(dir, "project");
  const outside = path.join(dir, "outside");
  await fs.mkdir(path.join(project, "node_modules", "package"), {
    recursive: true,
  });
  await fs.mkdir(path.join(project, "packages", "app", "node_modules"), {
    recursive: true,
  });
  await fs.mkdir(path.join(project, ".venv", "lib"), { recursive: true });
  await fs.mkdir(path.join(project, "src"), { recursive: true });
  await fs.mkdir(outside);
  await fs.writeFile(
    path.join(project, "node_modules", "package", "a.js"),
    "a".repeat(10),
  );
  await fs.writeFile(
    path.join(project, "packages", "app", "node_modules", "b.js"),
    "b".repeat(20),
  );
  await fs.writeFile(
    path.join(project, ".venv", "lib", "c.py"),
    "c".repeat(30),
  );
  await fs.writeFile(path.join(project, "src", "index.js"), "source");
  await fs.writeFile(path.join(project, "package-lock.json"), "lock");
  await fs.writeFile(path.join(outside, "keep.txt"), "keep");
  await fs.symlink(outside, path.join(project, "linked-dependencies"));

  const plan = await dependencyCleanupPlan(project);
  assert.deepEqual(plan.directories.map((item) => item.relativePath).sort(), [
    ".venv",
    "node_modules",
    path.join("packages", "app", "node_modules"),
  ]);
  assert.equal(plan.size, 60);

  const result = await cleanProjectDependencies(project);
  assert.deepEqual(result, { removed: 3, reclaimed: 60 });
  assert.equal(await exists(path.join(project, "node_modules")), false);
  assert.equal(await exists(path.join(project, ".venv")), false);
  assert.equal(
    await exists(path.join(project, "packages", "app", "node_modules")),
    false,
  );
  assert.equal(
    await fs.readFile(path.join(project, "src", "index.js"), "utf8"),
    "source",
  );
  assert.equal(
    await fs.readFile(path.join(project, "package-lock.json"), "utf8"),
    "lock",
  );
  assert.equal(
    await fs.readFile(path.join(outside, "keep.txt"), "utf8"),
    "keep",
  );
});
