import test from "node:test";
import assert from "node:assert/strict";
import {
  createSearchItems,
  searchProjects,
} from "../shared/project-search.mjs";

const projects = [
  {
    id: "same-id",
    name: "mobile-app",
    path: "/code/mobile",
    tags: ["用户端"],
    stacks: ["Node.js"],
    createdAt: 1,
    lastOpened: 1,
  },
];
const workspaces = [
  {
    id: "same-id",
    name: "商城系统",
    path: "/groups/shop",
    createdAt: 2,
    lastOpened: 0,
    members: [{ projectId: "same-id", alias: "app" }],
  },
];

test("mixed search finds groups by fuzzy name, path and member names without mutating projects", () => {
  const before = JSON.stringify(projects);
  const items = createSearchItems(projects, workspaces);
  for (const query of ["商城", "商系", "/groups/shop", "mobile-app", "app"]) {
    assert.ok(
      searchProjects(items, query).some((item) => item.kind === "workspace"),
      query,
    );
  }
  const results = searchProjects(items, "mobile-app");
  assert.equal(results.length, 2);
  assert.equal(results[0].id, "same-id");
  assert.equal(results[1].id, "workspace:same-id");
  assert.equal(results[1].workspaceId, "same-id");
  assert.match(results[1].searchMatch.reasons.join(" "), /成员：mobile-app/);
  assert.equal(JSON.stringify(projects), before);
  assert.equal(results[1].remote, undefined);
  assert.equal(results[1].favorite, false);
});

test("same-name project and group remain distinct; invalid groups stay searchable", () => {
  const items = createSearchItems(projects, [
    { ...workspaces[0], name: "mobile-app", error: "目录不存在" },
  ]);
  const results = searchProjects(items, "mobile-app");
  assert.equal(results.length, 2);
  assert.notEqual(results[0].id, results[1].id);
  assert.equal(results.find((item) => item.kind === "workspace").missing, true);
  assert.equal(searchProjects(items, "not-a-match").length, 0);
});
