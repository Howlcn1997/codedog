import test from "node:test";
import assert from "node:assert/strict";
import { searchProjects } from "../shared/project-search.mjs";

const base = {
  path: "/projects/example",
  tags: [],
  aliases: [],
  notes: "",
  stacks: [],
  dependencies: [],
  createdAt: 0,
  lastOpened: 0,
};

test("purpose search explains README and dependency matches with ranked results", () => {
  const projects = [
    {
      ...base,
      id: "readme",
      name: "toolbox",
      searchIndex: {
        description: "",
        dependencies: [],
        readme: { file: "README.md", text: "支持图片压缩和格式转换" },
      },
    },
    {
      ...base,
      id: "dependency",
      name: "worker",
      searchIndex: { description: "", dependencies: ["sharp"] },
    },
    { ...base, id: "name", name: "sharp-images" },
  ];

  const readme = searchProjects(projects, "图片压缩");
  assert.deepEqual(
    readme.map((project) => project.id),
    ["readme"],
  );
  assert.match(readme[0].searchMatch.reasons[0], /^README：.*图片压缩/);

  const sharp = searchProjects(projects, "SHARP");
  assert.deepEqual(
    sharp.map((project) => project.id),
    ["name", "dependency"],
  );
  assert.equal(sharp[1].searchMatch.reasons[0], "依赖：sharp");
});

test("empty purpose search preserves the existing project order", () => {
  const projects = [
    { ...base, id: "second", name: "Zulu" },
    { ...base, id: "first", name: "Alpha" },
  ];
  assert.deepEqual(
    searchProjects(projects, "").map((project) => project.id),
    ["second", "first"],
  );
});
