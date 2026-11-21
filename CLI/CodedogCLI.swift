import ArgumentParser
import CodedogCore

@main
struct CodedogCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "codedog",
        abstract: "在终端里查找并打开你的项目。",
        version: Codedog.version
    )
}
