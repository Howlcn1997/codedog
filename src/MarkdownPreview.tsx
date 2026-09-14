import { useEffect, useRef, useState } from "react";
import Markdown, { type Components } from "react-markdown";
import remarkGfm from "remark-gfm";

// Mermaid has global configuration, so serialize renders across diagrams/themes.
let renderQueue: Promise<unknown> = Promise.resolve();
let diagramId = 0;

function MermaidDiagram({ source }: { source: string }) {
  const container = useRef<HTMLDivElement>(null);
  const [dark, setDark] = useState(false);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const media = matchMedia("(prefers-color-scheme: dark)");
    const update = () => {
      const theme = document.documentElement.dataset.theme;
      setDark(theme === "dark" || (theme !== "light" && media.matches));
    };
    const observer = new MutationObserver(update);
    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ["data-theme"],
    });
    media.addEventListener("change", update);
    update();
    return () => {
      observer.disconnect();
      media.removeEventListener("change", update);
    };
  }, []);

  useEffect(() => {
    let cancelled = false;
    const host = container.current!;
    host.replaceChildren();
    setError("");
    setLoading(true);
    const task = async () => {
      if (cancelled) return;
      const { default: mermaid } = await import("mermaid");
      if (cancelled) return;
      mermaid.initialize({
        startOnLoad: false,
        securityLevel: "strict",
        theme: dark ? "dark" : "default",
        suppressErrorRendering: true,
      });
      const { svg } = await mermaid.render(
        `workspace-diagram-${++diagramId}`,
        source,
      );
      if (!cancelled) host.innerHTML = svg;
    };
    renderQueue = renderQueue
      .then(task)
      .catch((reason: unknown) => {
        if (!cancelled)
          setError(reason instanceof Error ? reason.message : String(reason));
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [source, dark]);

  return (
    <div className="markdown-diagram">
      {loading && (
        <p className="muted" role="status">
          正在绘制图表…
        </p>
      )}
      <div
        ref={container}
        role="img"
        aria-label="Mermaid 关系图"
        hidden={!!error || loading}
      />
      {error && (
        <div className="markdown-diagram-error">
          <p role="alert">图表语法有误，暂时无法渲染。</p>
          <details>
            <summary>查看源码与错误</summary>
            <pre>
              <code>{source}</code>
            </pre>
            <pre>{error}</pre>
          </details>
        </div>
      )}
    </div>
  );
}

const components: Components = {
  pre({ node, children }) {
    const code = node?.children[0];
    if (
      code?.type === "element" &&
      code.tagName === "code" &&
      Array.isArray(code.properties.className) &&
      code.properties.className.includes("language-mermaid")
    ) {
      const source = code.children
        .map((child) => (child.type === "text" ? child.value : ""))
        .join("");
      return <MermaidDiagram source={source} />;
    }
    return <pre>{children}</pre>;
  },
  table({ children }) {
    return (
      <div className="markdown-table">
        <table>{children}</table>
      </div>
    );
  },
};

export default function MarkdownPreview({ source }: { source: string }) {
  return (
    <div className="workspace-readme markdown-body">
      <Markdown remarkPlugins={[remarkGfm]} components={components} skipHtml>
        {source || "尚未填写关系说明。"}
      </Markdown>
    </div>
  );
}
