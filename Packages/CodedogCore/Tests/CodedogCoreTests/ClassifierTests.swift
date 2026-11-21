import Foundation
import Testing
@testable import CodedogCore

@Suite struct ClassifierTests {
    func classify(_ files: [String: String]) throws -> ProjectClassifier.Result {
        let f = try Fixture()
        for (k, v) in files { try f.file(k, v) }
        return ProjectClassifier.classify(path: f.root, markers: FolderScanner.markers(at: f.root))
    }

    @Test func reactAppIsWebTypeScript() throws {
        let r = try classify(["package.json": #"{"description":"控制台","dependencies":{"react":"19"},"devDependencies":{"typescript":"5"}}"#])
        #expect(r.stacks == [.typescript])
        #expect(r.kind == .web)
        #expect(r.description == "控制台")
    }

    @Test func electronIsApp() throws {
        #expect(try classify(["package.json": #"{"devDependencies":{"electron":"1"}}"#]).kind == .app)
    }

    @Test func devOnlyServerDepIsNotService() throws {
        #expect(try classify(["package.json": #"{"main":"index.js","devDependencies":{"express":"4"}}"#]).kind == .library)
    }

    @Test func nodeBinIsTool() throws {
        #expect(try classify(["package.json": #"{"bin":{"x":"cli.js"}}"#]).kind == .tool)
    }

    @Test func goServiceAndCli() throws {
        #expect(try classify(["go.mod": "module a\n", "internal/x.go": ""]).kind == .service)
        #expect(try classify(["go.mod": "module a\n", "cmd/a/main.go": ""]).kind == .tool)
    }

    @Test func pythonFastAPIIsService() throws {
        let r = try classify(["pyproject.toml": "[project]\ndescription = \"接口\"\ndependencies = [\"fastapi\"]\n"])
        #expect(r.stacks == [.python])
        #expect(r.kind == .service)
        #expect(r.description == "接口")
    }

    @Test func xcodeProjectIsSwiftApp() throws {
        let f = try Fixture()
        try f.dir("Demo.xcodeproj")
        let r = ProjectClassifier.classify(path: f.root, markers: FolderScanner.markers(at: f.root))
        #expect(r.stacks == [.swift])
        #expect(r.kind == .app)
    }

    @Test func staticHTMLIsWeb() throws {
        let r = try classify(["index.html": "<html>"])
        #expect(r.stacks == [.html])
        #expect(r.kind == .web)
    }

    @Test func readmeSummarySkipsNoise() throws {
        let readme = """
        # Title
        [![badge](x)](y)
        <p align="center">logo</p>

        A **quiet** home for [all](http://x) your projects.
        """
        let r = try classify(["README.md": readme, "index.html": ""])
        #expect(r.readmeFile == "README.md")
        #expect(r.description == "A quiet home for all your projects.")
    }
}

@Suite struct DependencyParsingTests {
    @Test func goModules() {
        let mod = "module a\n\nrequire (\n\tgithub.com/gin-gonic/gin v1.9.0\n\tgolang.org/x/net v0.1.0 // indirect\n)\nrequire github.com/x/y v1.0.0\n"
        #expect(ProjectClassifier.goDependencies(mod) == ["github.com/gin-gonic/gin", "golang.org/x/net", "github.com/x/y"])
    }

    @Test func python() {
        let deps = ProjectClassifier.pythonDependencies(
            requirements: "# c\nrequests==2.0\nuvicorn[standard]>=0.1\n-r other.txt\n",
            pyproject: "[project]\ndependencies = [\n  \"fastapi>=0.1\",\n  'pydantic'\n]\n")
        #expect(deps == ["requests", "uvicorn", "fastapi", "pydantic"])
    }

    @Test func cargo() {
        let deps = ProjectClassifier.cargoDependencies("[package]\nname = \"x\"\n[dependencies]\nserde = \"1\"\ntokio = { version = \"1\" }\n[dev-dependencies]\ninsta = \"1\"\n[features]\nfoo = []\n")
        #expect(deps == ["serde", "tokio", "insta"])
    }
}
