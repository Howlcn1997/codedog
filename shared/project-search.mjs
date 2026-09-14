export const normalizeSearchText = (value) =>
  String(value || "")
    .normalize("NFKC")
    .toLocaleLowerCase();

function fuzzy(value, query) {
  let index = 0;
  for (const character of normalizeSearchText(value)) {
    if (character === query[index]) index++;
  }
  return index === query.length;
}

function readmeSnippet(text, query) {
  const clean = text.replace(/\s+/g, " ").trim();
  const normalized = normalizeSearchText(clean);
  const terms = normalizeSearchText(query).split(/\s+/).filter(Boolean);
  const positions = terms
    .map((term) => normalized.indexOf(term))
    .filter((index) => index >= 0);
  const hit = positions.length ? Math.min(...positions) : 0;
  const start = Math.max(0, hit - 24);
  const end = Math.min(
    clean.length,
    hit + Math.max(...terms.map((term) => term.length), 1) + 46,
  );
  return `${start ? "…" : ""}${clean.slice(start, end)}${end < clean.length ? "…" : ""}`;
}

// Read-only presentation records for mixed desktop search. These never enter
// the project store; mutations and opening must route by workspaceId.
export function createSearchItems(projects, workspaces = []) {
  const byId = new Map(projects.map((project) => [project.id, project]));
  return [
    ...projects,
    ...workspaces.map((workspace) => ({
      kind: "workspace",
      workspaceId: workspace.id,
      id: `workspace:${workspace.id}`,
      name: workspace.name,
      path: workspace.path,
      createdAt: workspace.createdAt,
      lastOpened: workspace.lastOpened,
      memberCount: workspace.members.length,
      memberNames: workspace.members
        .flatMap((member) => [member.alias, byId.get(member.projectId)?.name])
        .filter(Boolean),
      group: "",
      tags: [],
      notes: "",
      favorite: false,
      archived: false,
      stacks: [],
      environments: [],
      dependencies: [],
      dependencyState: "",
      missing: !!workspace.error,
      error: workspace.error,
      description: `${workspace.members.length} 个成员项目`,
    })),
  ];
}

export function matchProject(project, query) {
  const terms = normalizeSearchText(query).trim().split(/\s+/).filter(Boolean);
  if (!terms.length) return undefined;
  const index = project.searchIndex;
  const fields = [
    { key: "name", rank: 0, values: [project.name], label: "名称" },
    { key: "tag", rank: 0, values: project.tags || [], label: "标签" },
    { key: "alias", rank: 0, values: project.aliases || [], label: "别名" },
    {
      key: "member",
      rank: 1,
      values: project.memberNames || [],
      label: "成员",
    },
    {
      key: "description",
      rank: 1,
      values: [index?.description || project.description],
      label: "描述",
    },
    { key: "notes", rank: 1, values: [project.notes], label: "备注" },
    { key: "path", rank: 1, values: [project.path], label: "路径" },
    { key: "remote", rank: 1, values: [project.remote], label: "远程地址" },
    { key: "stack", rank: 1, values: project.stacks || [], label: "技术栈" },
    {
      key: "dependency",
      rank: 2,
      values:
        index?.dependencies ||
        (project.dependencies || []).map((item) => item.name),
      label: "依赖",
    },
    { key: "readme", rank: 2, values: [index?.readme?.text], label: "README" },
  ].map((field) => ({
    ...field,
    values: field.values.filter(Boolean).map(String),
  }));

  const termRanks = [];
  for (const term of terms) {
    const ranks = fields
      .filter(
        (field) =>
          field.values.some((value) =>
            normalizeSearchText(value).includes(term),
          ) ||
          ((field.key === "name" || field.key === "alias") &&
            field.values.some((value) => fuzzy(value, term))),
      )
      .map((field) => field.rank);
    if (!ranks.length) return null;
    termRanks.push(Math.min(...ranks));
  }
  const phrase = normalizeSearchText(query).trim();
  const matchedFields = fields
    .filter(
      (field) =>
        field.values.some((value) =>
          normalizeSearchText(value).includes(phrase),
        ) ||
        terms.some((term) =>
          field.values.some(
            (value) =>
              normalizeSearchText(value).includes(term) ||
              ((field.key === "name" || field.key === "alias") &&
                fuzzy(value, term)),
          ),
        ),
    )
    .sort((a, b) => a.rank - b.rank);
  const reasons = matchedFields.slice(0, 2).map((field) => {
    if (field.key === "readme")
      return `README：${readmeSnippet(index?.readme?.text || "", query)}`;
    const value = field.values.find((item) =>
      terms.some(
        (term) =>
          normalizeSearchText(item).includes(term) ||
          ((field.key === "name" || field.key === "alias") &&
            fuzzy(item, term)),
      ),
    );
    return `${field.label}：${value || field.values[0]}`;
  });
  return { rank: Math.max(...termRanks), reasons };
}

export function searchProjects(projects, query = "", compare = () => 0) {
  const hasQuery = !!query.trim();
  return projects
    .map((project) => ({ project, match: matchProject(project, query) }))
    .filter((item) => item.match !== null)
    .sort((a, b) => {
      if (hasQuery) {
        const rank = (a.match?.rank ?? 0) - (b.match?.rank ?? 0);
        if (rank) return rank;
      }
      return compare(a.project, b.project);
    })
    .map(({ project, match }) =>
      match ? { ...project, searchMatch: match } : project,
    );
}

export function resolveProject(projects, query) {
  const needle = normalizeSearchText(query).trim();
  if (!needle) throw Error("请提供项目名称或别名");
  const aliases = projects.filter((project) =>
    (project.aliases || []).some(
      (alias) => normalizeSearchText(alias) === needle,
    ),
  );
  if (aliases.length === 1) return { project: aliases[0], candidates: [] };
  if (aliases.length > 1) return { project: null, candidates: aliases };
  const names = projects.filter(
    (project) => normalizeSearchText(project.name) === needle,
  );
  if (names.length === 1) return { project: names[0], candidates: [] };
  if (names.length > 1) return { project: null, candidates: names };
  const candidates = searchProjects(projects, query);
  return candidates.length === 1
    ? { project: candidates[0], candidates: [] }
    : { project: null, candidates };
}
