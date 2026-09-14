import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import { ProjectStore } from "../electron/core.mjs";
import {
  createWorkspace,
  getWorkspace,
  workspaceLocation,
  updateWorkspace,
  listWorkspaces,
  repairWorkspace,
  forgetWorkspace,
} from "../electron/workspaces.mjs";

async function fixture(t) {
  const dir = await fs.realpath(
    await fs.mkdtemp(path.join(os.tmpdir(), "codedog-workspaces-")),
  );
  t.after(() => fs.rm(dir, { recursive: true, force: true }));
  t.mock.method(os, "homedir", () => dir);
  const store = new ProjectStore(path.join(dir, "data.json"));
  await store.init();
  await store.setRoot(dir);
  const projects = [];
  for (const name of ["app", "web", "api"]) {
    const folder = path.join(dir, name);
    await fs.mkdir(folder);
    await fs.writeFile(path.join(folder, "source.txt"), name);
    projects.push({ id: name, name, path: folder });
  }
  store.state.projects = projects;
  await store.save();
  const input = {
    name: "商城系统",
    description: "# 项目关系\napp → api",
    members: projects.map((p) => ({ projectId: p.id, alias: p.name })),
  };
  return { store, dir, projects, input };
}

test("project groups persist, share projects, and expose original source through links", async (t) => {
  const { store, input } = await fixture(t);
  const first = await createWorkspace(store, input);
  const second = await createWorkspace(store, { ...input, name: "运营系统" });
  await fs.writeFile(path.join(first.path, "app", "source.txt"), "changed");
  assert.equal(
    await fs.readFile(path.join(second.path, "app", "source.txt"), "utf8"),
    "changed",
  );
  const reopened = new ProjectStore(store.file);
  await reopened.init();
  assert.equal(reopened.state.workspaces.length, 2);
  assert.equal(
    (await getWorkspace(reopened, first.id)).description,
    input.description,
  );
  assert.ok(
    (await listWorkspaces(reopened)).every((w) =>
      w.members.every((m) => m.status === "ready"),
    ),
  );
  assert.equal(reopened.state.projects.length, 3);
});

test("rename and remove members preserve source, custom files and stable group path", async (t) => {
  const { store, input, projects } = await fixture(t);
  const w = await createWorkspace(store, input);
  await fs.writeFile(path.join(w.path, "NOTES.md"), "user notes");
  const next = await updateWorkspace(store, w.id, {
    name: "新名称",
    members: [{ projectId: "app", alias: "mobile" }],
    description: "new",
    expectedDescription: input.description,
  });
  assert.equal(next.path, w.path);
  assert.equal(
    await fs.realpath(path.join(w.path, "mobile")),
    projects[0].path,
  );
  await assert.rejects(fs.lstat(path.join(w.path, "app")), { code: "ENOENT" });
  for (const p of projects)
    assert.equal(
      await fs.readFile(path.join(p.path, "source.txt"), "utf8"),
      p.name,
    );
  assert.equal(
    await fs.readFile(path.join(w.path, "NOTES.md"), "utf8"),
    "user notes",
  );
  await forgetWorkspace(store, w.id);
  assert.equal(store.state.workspaces.length, 0);
  assert.equal(
    await fs.readFile(path.join(w.path, "README.md"), "utf8"),
    "new",
  );
  assert.ok((await fs.lstat(path.join(w.path, "mobile"))).isSymbolicLink());
});

test("missing links and relocated projects can be repaired; missing source is reported", async (t) => {
  const { store, input, projects, dir } = await fixture(t);
  const w = await createWorkspace(store, input);
  await fs.unlink(path.join(w.path, "app"));
  assert.equal((await listWorkspaces(store))[0].members[0].status, "链接缺失");
  await repairWorkspace(store, w.id);
  assert.equal(await fs.realpath(path.join(w.path, "app")), projects[0].path);
  const moved = path.join(dir, "moved-app");
  await fs.rename(projects[0].path, moved);
  assert.notEqual((await listWorkspaces(store))[0].members[0].status, "ready");
  await store.transaction(async () => {
    store.state.projects[0].path = moved;
    await store.save();
  });
  await repairWorkspace(store, w.id);
  assert.equal(await fs.realpath(path.join(w.path, "app")), moved);
});

test("conflicting real directories, foreign symlinks and README symlinks are never overwritten", async (t) => {
  const { store, input, dir } = await fixture(t);
  const w = await createWorkspace(store, input);
  const file = path.join(w.path, "app");
  await fs.unlink(file);
  await fs.mkdir(file);
  await fs.writeFile(path.join(file, "keep.txt"), "keep");
  await assert.rejects(repairWorkspace(store, w.id), /已被替换/);
  await assert.rejects(
    updateWorkspace(store, w.id, { name: w.name, members: [] }),
    /已被替换/,
  );
  assert.equal(await fs.readFile(path.join(file, "keep.txt"), "utf8"), "keep");
  await fs.rm(file, { recursive: true });
  await fs.symlink(dir, file, "dir");
  await assert.rejects(repairWorkspace(store, w.id), /已被替换/);
  await fs.unlink(file);
  await repairWorkspace(store, w.id);
  await fs.unlink(path.join(w.path, "README.md"));
  const external = path.join(dir, "external.md");
  await fs.writeFile(external, "keep");
  await fs.symlink(external, path.join(w.path, "README.md"));
  await assert.rejects(getWorkspace(store, w.id), /普通文件/);
  assert.equal((await workspaceLocation(store, w.id)).path, w.path);
  await repairWorkspace(store, w.id);
  await assert.rejects(
    updateWorkspace(store, w.id, { ...input, expectedDescription: "keep" }),
    /普通文件/,
  );
  assert.equal(await fs.readFile(external, "utf8"), "keep");
});

test("reject traversal, portable-name collisions, repeated targets and recursive topology", async (t) => {
  const { store, input, projects } = await fixture(t);
  for (const alias of [
    "../escape",
    "..",
    "a/b",
    "CON",
    "README.md",
    ".codedog-workspace.json",
  ]) {
    await assert.rejects(
      createWorkspace(store, {
        ...input,
        members: [{ projectId: "app", alias }],
      }),
    );
  }
  await assert.rejects(
    createWorkspace(store, {
      ...input,
      members: [
        { projectId: "app", alias: "App" },
        { projectId: "web", alias: "app" },
      ],
    }),
    /重复/,
  );
  await assert.rejects(
    createWorkspace(store, {
      ...input,
      members: [
        { projectId: "app", alias: "one" },
        { projectId: "app", alias: "two" },
      ],
    }),
    /重复/,
  );
});

test("save failure rolls back new directories and edits without damaging source", async (t) => {
  const { store, input, dir } = await fixture(t);
  const save = store.save.bind(store);
  store.save = async () => {
    throw Error("disk full");
  };
  await assert.rejects(createWorkspace(store, input), /disk full/);
  assert.deepEqual(
    await fs.readdir(path.join(dir, "codespace", "workspaces")),
    [],
  );
  store.save = save;
  const w = await createWorkspace(store, input);
  store.save = async () => {
    throw Error("disk full");
  };
  await assert.rejects(
    updateWorkspace(store, w.id, {
      name: "changed",
      members: [{ projectId: "app", alias: "mobile" }],
      description: "changed",
      expectedDescription: input.description,
    }),
    /disk full/,
  );
  assert.equal(
    (await getWorkspace(store, w.id)).description,
    input.description,
  );
  for (const member of input.members)
    assert.ok(
      (await fs.lstat(path.join(w.path, member.alias))).isSymbolicLink(),
    );
  await assert.rejects(fs.lstat(path.join(w.path, "mobile")), {
    code: "ENOENT",
  });
  assert.equal(store.state.workspaces[0].name, input.name);
});

test("external README edits are preserved and referenced projects cannot be forgotten", async (t) => {
  const { store, input, dir } = await fixture(t);
  const w = await createWorkspace(store, input);
  await fs.writeFile(path.join(w.path, "README.md"), "external edit");
  await assert.rejects(
    updateWorkspace(store, w.id, {
      ...input,
      expectedDescription: input.description,
    }),
    /外部修改/,
  );
  await repairWorkspace(store, w.id);
  assert.equal((await getWorkspace(store, w.id)).description, "external edit");
  await assert.rejects(store.forget("app"), /仍被项目组/);
  await assert.rejects(store.setRoot(path.join(dir, "app")), /项目组/);
  await forgetWorkspace(store, w.id);
  await store.forget("app");
});

test("empty groups work with old data, missing directories can be forgotten", async (t) => {
  const { store, input } = await fixture(t);
  assert.deepEqual(await listWorkspaces(store), []);
  const w = await createWorkspace(store, { ...input, members: [] });
  await fs.rename(w.path, `${w.path}-moved`);
  assert.match((await listWorkspaces(store))[0].error, /不存在或已被替换/);
  await assert.rejects(getWorkspace(store, w.id));
  await forgetWorkspace(store, w.id);
  assert.equal(store.state.workspaces.length, 0);
});

test("creation uses fixed home directory regardless of root or supplied parent", async (t) => {
  const { store, input, dir, projects } = await fixture(t);
  store.state.root = "";
  await store.save();
  const created = await createWorkspace(store, {
    ...input,
    parent: projects[0].path,
  });
  assert.equal(
    path.dirname(created.path),
    path.join(dir, "codespace", "workspaces"),
  );
});

test("fixed workspace directory cannot be nested inside a member project", async (t) => {
  const { store, input, dir, projects } = await fixture(t);
  projects[0].path = dir;
  await store.save();
  await assert.rejects(createWorkspace(store, input), /互相包含/);
});
