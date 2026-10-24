import Foundation

func printToStdErr(_ message: String) {
  fputs("\(message)\n", stderr)
}

CommandLineInterpreter()
  .interpret(
    arguments: Array(CommandLine.arguments.dropFirst())
  )
