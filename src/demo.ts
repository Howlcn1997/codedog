import type { State, Project, Group } from "./types";
const rows: [string, Group, string, string, string[]][] = [
  [
    "atlas-console",
    "company",
    "Node.js",
    "内部管理平台与运营工作台",
    ["前端", "React"],
  ],
  [
    "gateway-service",
    "company",
    "Go",
    "统一网关与身份认证服务",
    ["后端", "API"],
  ],
  ["data-pipeline", "company", "Python", "数据采集、清洗与分析流程", ["数据"]],
  [
    "design-system",
    "company",
    "Node.js",
    "团队共享的界面组件与设计规范",
    ["设计", "组件库"],
  ],
  [
    "personal-site",
    "personal",
    "Node.js",
    "记录作品与灵感的个人空间",
    ["网站"],
  ],
  ["dev-notes", "personal", "Node.js", "开发笔记与知识整理", ["工具"]],
  ["cli-toolkit", "personal", "Go", "让日常工作更轻松的命令行工具", ["CLI"]],
  ["api-playground", "temporary", "Python", "新接口与想法的试验场", ["实验"]],
];
export const demo: State = {
  root: "~/Projects",
  ide: "Cursor",
  projects: rows.map(([name, group, stack, description, tags], i): Project => ({
    id: `demo-${i}`,
    name,
    path: `~/Projects/${group}/${name}`,
    group,
    tags,
    description,
    notes: "",
    favorite: i === 0 || i === 4,
    archived: false,
    createdAt: Date.now() - 86400000 * i,
    lastOpened: Date.now() - i * 3600000,
    stacks: [stack],
    branch: "main",
    changes: i === 0 ? 3 : 0,
    remote: `git@github.com:example/${name}.git`,
    dependencyState:
      stack === "Python" ? "pending" : stack === "Go" ? "unknown" : "ready",
    environments: [
      {
        stack,
        declared:
          stack === "Node.js" ? ">=22" : stack === "Go" ? "1.24" : ">=3.12",
        manager: stack === "Node.js" ? "pnpm" : stack === "Go" ? "go" : "uv",
        manifest:
          stack === "Node.js"
            ? "package.json"
            : stack === "Go"
              ? "go.mod"
              : "pyproject.toml",
        location:
          stack === "Node.js"
            ? "node_modules"
            : stack === "Go"
              ? "共享模块缓存"
              : ".venv",
        installed: stack === "Go" ? null : stack !== "Python",
      },
    ],
    dependencies:
      stack === "Node.js"
        ? [
            { name: "react", version: "^19.0.0", kind: "生产", stack },
            { name: "typescript", version: "^5.8.0", kind: "开发", stack },
            { name: "vite", version: "^7.0.0", kind: "开发", stack },
            { name: "lucide-react", version: "^0.468.0", kind: "生产", stack },
          ]
        : [],
  })),
};
