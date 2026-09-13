export type Theme = "system" | "light" | "dark";
export type Group = string;
export type Environment = {
  stack: string;
  declared: string;
  manager: string;
  manifest: string;
  location: string;
  installed: boolean | null;
  version?: string;
  managerVersion?: string;
};
export type Dependency = {
  name: string;
  version: string;
  kind: string;
  stack: string;
};
export type SearchIndex = {
  version: number;
  updatedAt: number;
  description: string;
  dependencies: string[];
  readme?: { file: string; text: string };
};
export type Project = {
  id: string;
  name: string;
  path: string;
  group: Group;
  tags: string[];
  aliases?: string[];
  notes: string;
  favorite: boolean;
  archived: boolean;
  createdAt: number;
  lastOpened: number;
  ide?: string;
  stacks: string[];
  description?: string;
  dependencyState: string;
  environments: Environment[];
  dependencies: Dependency[];
  branch?: string;
  changes?: number;
  remote?: string;
  missing?: boolean;
  error?: string;
  searchIndex?: SearchIndex;
};
export type ProjectSearchResult = Project & {
  searchMatch?: { rank: number; reasons: string[] };
};
export type SavedFilter = {
  id: string;
  name: string;
  query: string;
  group: string;
  stack: string;
  tag: string;
  sort: string;
};
export type State = {
  groups?: Record<string, string>;
  theme?: Theme;
  terminal?: "system" | "warp";
  root: string;
  ide: string;
  projects: Project[];
  savedFilters?: SavedFilter[];
  launcherShortcut?: string;
  uiMode?: "standard" | "compact";
};
export type ImportInput = {
  copyClaudeChats: boolean;
  tags: string[];
  mode: string;
  source: string;
  url: string;
  name: string;
  group: Group;
};
export type Api = {
  initialMode: "standard" | "compact";
  createGroup: (name: string) => Promise<{ id: string; name: string }>;
  setTheme: (theme: Theme) => Promise<void>;
  setTerminal: (terminal: "system" | "warp") => Promise<void>;
  projectMenu: (id: string) => Promise<{ opened: boolean }>;
  setMode: (mode: "standard" | "compact") => Promise<void>;
  setSavedFilters: (filters: SavedFilter[]) => Promise<void>;
  setLauncherShortcut: (shortcut: string) => Promise<string>;
  cliStatus: () => Promise<{ installed: boolean; path: string }>;
  installCli: () => Promise<{ path: string }>;
  hideLauncher: () => Promise<void>;
  state: () => Promise<State>;
  pickFolder: () => Promise<string | null>;
  setRoot: (folder: string) => Promise<void>;
  setIde: (ide: string) => Promise<void>;
  import: (input: ImportInput) => Promise<void>;
  scan: (folder: string) => Promise<string[]>;
  refreshSearchIndex: (id?: string) => Promise<number>;
  update: (id: string, patch: Partial<Project>) => Promise<void>;
  forget: (id: string) => Promise<void>;
  open: (id: string, kind: string) => Promise<void>;
  copy: (id: string) => Promise<void>;
  storage: (
    id: string,
  ) => Promise<{ source: number; dependencies: number; skipped: number }>;
  storageBatch: (
    ids: string[],
  ) => Promise<
    Record<string, { source: number; dependencies: number; skipped: number }>
  >;
  cleanupDependenciesPreview: (ids: string[]) => Promise<{
    size: number;
    directories: {
      projectId: string;
      projectName: string;
      path: string;
      size: number;
    }[];
  }>;
  cleanupDependencies: (ids: string[]) => Promise<{
    canceled: boolean;
    reclaimed?: number;
    projects?: { id: string; removed: number; reclaimed: number }[];
  }>;
  environment: (id: string) => Promise<Environment[]>;
  install: (id: string, stack: string) => Promise<{ canceled: boolean }>;
  backup: () => Promise<boolean>;
  openRoot: () => Promise<void>;
  onLog: (callback: (text: string) => void) => () => void;
  onModeChange: (
    callback: (mode: "standard" | "compact") => void,
  ) => () => void;
  onSearchIndexUpdated: (callback: () => void) => () => void;
};
declare global {
  interface Window {
    codedog?: Api;
  }
}
