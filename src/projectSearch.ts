import type { Project, ProjectSearchResult } from "./types";

const normalize = (value: unknown) =>
  String(value || "")
    .normalize("NFKC")
    .toLocaleLowerCase();

function fuzzy(value: string, query: string) {
  let index = 0;
  for (const character of normalize(value)) {
    if (character === query[index]) index++;
  }
  return index === query.length;
}

function readmeSnippet(text: string, query: string) {
  const clean = text.replace(/\s+/g, " ").trim();
  const normalized = normalize(clean);
  const terms = normalize(query).split(/\s+/).filter(Boolean);
  const positions = terms.map((term) => normalized.indexOf(term)).filter((i) => i >= 0);
  const hit = positions.length ? Math.min(...positions) : 0;
  const start = Math.max(0, hit - 24);
  const end = Math.min(clean.length, hit + Math.max(...terms.map((t) => t.length), 1) + 46);
  return `${start ? "…" : ""}${clean.slice(start, end)}${end < clean.length ? "…" : ""}`;
}

export function matchProject(
  project: Project,
  query: string,
): ProjectSearchResult["searchMatch"] | null {
  const terms = normalize(query).trim().split(/\s+/).filter(Boolean);
  if (!terms.length) return undefined;
  const index = project.searchIndex;
  const fields = [
    { key: "name", rank: 0, values: [project.name], label: "名称" },
    { key: "tag", rank: 0, values: project.tags, label: "标签" },
    { key: "alias", rank: 0, values: project.aliases || [], label: "别名" },
    { key: "description", rank: 1, values: [index?.description || project.description], label: "描述" },
    { key: "notes", rank: 1, values: [project.notes], label: "备注" },
    { key: "path", rank: 1, values: [project.path], label: "路径" },
    { key: "remote", rank: 1, values: [project.remote], label: "远程地址" },
    { key: "stack", rank: 1, values: project.stacks, label: "技术栈" },
    { key: "dependency", rank: 2, values: index?.dependencies || project.dependencies.map((d) => d.name), label: "依赖" },
    { key: "readme", rank: 2, values: [index?.readme?.text], label: "README" },
  ].map((field) => ({ ...field, values: field.values.filter(Boolean).map(String) }));

  const termRanks: number[] = [];
  for (const term of terms) {
    const ranks = fields
      .filter((field) =>
        field.values.some((value) => normalize(value).includes(term)) ||
        ((field.key === "name" || field.key === "alias") &&
          field.values.some((value) => fuzzy(value, term))),
      )
      .map((field) => field.rank);
    if (!ranks.length) return null;
    termRanks.push(Math.min(...ranks));
  }

  const phrase = normalize(query).trim();
  const matchedFields = fields
    .filter((field) =>
      field.values.some((value) => normalize(value).includes(phrase)) ||
      terms.some((term) => field.values.some((value) => normalize(value).includes(term))),
    )
    .sort((a, b) => a.rank - b.rank);
  const reasons = matchedFields.slice(0, 2).map((field) => {
    if (field.key === "readme")
      return `README：${readmeSnippet(index?.readme?.text || "", query)}`;
    const value = field.values.find((item) =>
      terms.some((term) => normalize(item).includes(term)),
    );
    return `${field.label}：${value || field.values[0]}`;
  });
  return { rank: Math.max(...termRanks), reasons };
}

export function searchProjects(
  projects: Project[],
  query: string,
  compare: (a: Project, b: Project) => number,
): ProjectSearchResult[] {
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
