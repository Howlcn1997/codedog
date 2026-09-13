import type { Project, ProjectSearchResult } from "./types";
// The renderer and CLI intentionally consume the same pure matching module.
// @ts-expect-error TypeScript-facing signatures are declared by these wrappers.
import * as shared from "../shared/project-search.mjs";

export function matchProject(
  project: Project,
  query: string,
): ProjectSearchResult["searchMatch"] | null | undefined {
  return shared.matchProject(project, query);
}

export function searchProjects(
  projects: Project[],
  query: string,
  compare: (a: Project, b: Project) => number,
): ProjectSearchResult[] {
  return shared.searchProjects(projects, query, compare);
}
