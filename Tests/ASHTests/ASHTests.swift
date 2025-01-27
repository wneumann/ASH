import XCTest
@testable import ASH

final class AshTests: XCTestCase {
  let fm = FileManager.default
  let ash = ASH.shared
  
  override class func setUp() {
    let fm = FileManager.default
    let files = (1...5).map { "I am file \($0)!".data(using: .utf8) }

    let tempDir = fm.temporaryDirectory
    do {
      try fm.createDirectory(at: tempDir.appendingPathComponent("dir1/subdir1", isDirectory: true), withIntermediateDirectories: true, attributes: nil)
      try fm.createDirectory(at: tempDir.appendingPathComponent("dir1/subdir2", isDirectory: true), withIntermediateDirectories: true, attributes: nil)
      try fm.createDirectory(at: tempDir.appendingPathComponent("dir1/subdir3", isDirectory: true), withIntermediateDirectories: true, attributes: nil)
      fm.createFile(atPath: tempDir.appendingPathComponent("dir1/file1").path, contents: files[0], attributes: nil)
      fm.createFile(atPath: tempDir.appendingPathComponent("dir1/file2").path, contents: files[1], attributes: nil)
      fm.createFile(atPath: tempDir.appendingPathComponent("dir1/subdir1/file3").path, contents: files[2], attributes: nil)
      fm.createFile(atPath: tempDir.appendingPathComponent("dir1/subdir2/file4").path, contents: files[3], attributes: nil)
      fm.createFile(atPath: tempDir.appendingPathComponent("dir1/subdir2/file5").path, contents: files[4], attributes: nil)
//      print("basedir: \(tempDir.appendingPathComponent("dir1").path)")
//      print("created: \(try! fm.contentsOfDirectory(atPath: tempDir.appendingPathComponent("dir1").path))")
    } catch {
      fatalError("Setup got funky.")
    }
  }
  
  override class func tearDown() {
    print("***** Tearing shit down, yo!")
    let fm = FileManager.default
    let tempDir = fm.temporaryDirectory
    do {
      try fm.removeItem(at: tempDir.appendingPathComponent("dir1", isDirectory: true))
    } catch {
      fatalError("Could not delete contents of \(tempDir.appendingPathComponent("dir1", isDirectory: true))")
    }
  }
  
  func testLs() throws {
    let tempDir = fm.temporaryDirectory
    let basePath = tempDir.appendingPathComponent("dir1").path
    let expected = ["\(basePath):", "file1", "file2", "subdir1", "subdir2", "subdir3"].sorted()
    
    let command = try XCTUnwrap(Command("ls; \(basePath)"))
    XCTAssertEqual(command.command, .ls)
    XCTAssertEqual(command.filePath, basePath)
    let result = ash.command(command: "ls; \(basePath)")
    switch result {
    case .success(.string(let listing)):
      let contents = listing.split(separator: "\n").map(String.init)
      XCTAssertEqual(expected, contents.sorted())
    case .success(_), .failure: XCTAssert(false, "result: \(result)")
    }
  }
  
  func testLsEmpty() throws {
    let tempDir = fm.temporaryDirectory
    let basePath = tempDir.appendingPathComponent("dir1/subdir3").path
    let expected = ["\(basePath):"]
    
    let result = ash.command(command: "ls; \(basePath)")
    switch result {
    case .success(.string(let listing)):
      let contents = listing.split(separator: "\n").map(String.init)
      XCTAssertEqual(expected, contents.sorted())
    case .success(_), .failure: XCTAssert(false, "result: \(result)")
    }
  }
  
  func testCd() throws {
    let command = try XCTUnwrap(Command("cd; /usr/local/bin"))
    XCTAssertEqual(command.command, .cd)
    XCTAssertEqual(command.filePath, "/usr/local/bin")
    XCTAssertNotEqual(fm.currentDirectoryPath, "/usr/local/bin")
    let result = ash.command(command: "cd; /usr/local/bin")
    XCTAssertEqual(fm.currentDirectoryPath, "/usr/local/bin")
    switch result {
    case .success(let msg): XCTAssertEqual(msg, .string("/usr/local/bin"))
    case .failure(_): XCTAssert(false)
    }
  }
  
  func testCdRelative() {
    let tempDir = fm.temporaryDirectory
    let basePath = tempDir.path
    let targetPath = tempDir.appendingPathComponent("dir1/subdir2").path

    fm.changeCurrentDirectoryPath(basePath)
    let _ = ash.command(command: "cd; dir1/subdir2")
    // Stupid workaround for the /var -> /private/var symlink
    XCTAssertEqual(fm.currentDirectoryPath, "/private\(targetPath)")
  }
  
  func testCdFailure() {
    let tempDir = fm.temporaryDirectory
    let basePath = tempDir.path

    fm.changeCurrentDirectoryPath(basePath)
    let _ = ash.command(command: "cd; jibbajabba")
    // Stupid workaround for the /var -> /private/var symlink
    XCTAssertEqual(fm.currentDirectoryPath, "/private\(basePath)")
  }
  
  func testCdParent() {
    let tempDir = fm.temporaryDirectory
    let basePath = tempDir.path
    let targetPath = tempDir.deletingLastPathComponent().path

    fm.changeCurrentDirectoryPath(basePath)
    let _ = ash.command(command: "cd; ..")
    // Stupid workaround for the /var -> /private/var symlink
    XCTAssertEqual(fm.currentDirectoryPath, "/private\(targetPath)")
  }
  
  func testMkdir() throws {
    let command = try XCTUnwrap(Command("mkdir; testdir"))
    XCTAssertEqual(command.command, .mkdir)
    XCTAssertEqual(command.filePath, "testdir")

    let tempDir = fm.temporaryDirectory.appendingPathComponent("dir1", isDirectory: true)
    fm.changeCurrentDirectoryPath(tempDir.path)
    let targetPath = tempDir.appendingPathComponent("testdir", isDirectory: true).path
    switch ash.command(command: "mkdir; testdir") {
    case .failure(let error):
      XCTAssert(false, error.localizedDescription)
    case .success:
      var isDir: ObjCBool = false
      let exists = fm.fileExists(atPath: targetPath, isDirectory: &isDir)
      
      XCTAssert(exists && isDir.boolValue)
    }
  }
  
  func testMkdirFailure() {
    // non-writeable directory
    fm.changeCurrentDirectoryPath("/opt")
    switch ash.command(command: "mkdir; testdir") {
    case .failure:
      XCTAssert(true)
    case .success:
      var isDir: ObjCBool = false
      let exists = fm.fileExists(atPath: "/opt/testdir", isDirectory: &isDir)
      XCTAssert(exists && isDir.boolValue)
    }
  }
  
  func testWhoami() throws {
    let command = try XCTUnwrap(Command("whoami;"))
    XCTAssertEqual(command.command, .whoami)
    XCTAssertEqual(command.filePath, "")

    let result = ash.command(command: "whoami;")
    switch result {
    case .success(.string(let user)): XCTAssertEqual(user, NSUserName())
    case .success(_), .failure: XCTAssert(false)
    }
  }
  
  func testRm() throws {
    let command = try XCTUnwrap(Command("rm; junkFile"))
    XCTAssertEqual(command.command, .rm)
    XCTAssertEqual(command.filePath, "junkFile")

    let tempDir = fm.temporaryDirectory.appendingPathComponent("dir1", isDirectory: true)
    let targetFile = tempDir.appendingPathComponent("junkFile")
    fm.createFile(atPath: targetFile.path, contents: "just some junk".data(using: .utf8), attributes: nil)
    XCTAssert(fm.fileExists(atPath: targetFile.path))
    fm.changeCurrentDirectoryPath(tempDir.path)
    
    switch ash.command(command: "rm; junkFile") {
    case .success: XCTAssertFalse(fm.fileExists(atPath: targetFile.path))
    case .failure(let error): XCTAssert(false, error.localizedDescription)
    }
  }

  func testRmMultiple() throws {
    let tempDir = fm.temporaryDirectory.appendingPathComponent("dir1", isDirectory: true)
    let targetFiles: [String] = (1...5).map { i in
      let targetFile = tempDir.appendingPathComponent("junkFile\(i)")
      fm.createFile(atPath: targetFile.path, contents: "just some junk #\(i)".data(using: .utf8), attributes: nil)
      XCTAssert(fm.fileExists(atPath: targetFile.path))
      return targetFile.path
    }
    fm.changeCurrentDirectoryPath(tempDir.path)
    
    switch ash.command(command: "rm; \(targetFiles.joined(separator: "; "))") {
    case .success:
      for target in targetFiles { XCTAssertFalse(fm.fileExists(atPath: target)) }
    case .failure(let error):
      XCTAssert(false, error.localizedDescription)
    }
  }

  func testRmNonexistant() {
    let tempDir = fm.temporaryDirectory.appendingPathComponent("dir1", isDirectory: true)
    let targetFile = tempDir.appendingPathComponent("junkFile")
    XCTAssertFalse(fm.fileExists(atPath: targetFile.path))
    fm.changeCurrentDirectoryPath(tempDir.path)
    
    if case .success = ash.command(command: "rm; junkFile") {
      XCTAssert(false)
    }
  }

//  func testRMNoPermissions() {
//    // This one needs to be thought about -- I may need to add a delegate to a filemanager so
//    // it can't delete a 0o400 file
//  }

  func testRmDir() throws {
    let command = try XCTUnwrap(Command("rmdir; junkDir"))
    XCTAssertEqual(command.command, .rmdir)
    XCTAssertEqual(command.filePath, "junkDir")

    let tempDir = fm.temporaryDirectory.appendingPathComponent("dir1", isDirectory: true)
    let targetDir = tempDir.appendingPathComponent("junkDir", isDirectory: true)
    let targetFile = targetDir.appendingPathComponent("junkFile", isDirectory: true)
    try! fm.createDirectory(at: targetDir, withIntermediateDirectories: true, attributes: nil)
    fm.createFile(atPath: targetFile.path, contents: "just some junk".data(using: .utf8), attributes: nil)
    XCTAssert(fm.fileExists(atPath: targetFile.path))
    fm.changeCurrentDirectoryPath(tempDir.path)
    
    switch ash.command(command: "rmdir; junkDir") {
    case .success: XCTAssertFalse(fm.fileExists(atPath: targetFile.path))
    case .failure(let error): XCTAssert(false, error.localizedDescription)
    }
  }

  func testRmDirNonexistant() {
    let tempDir = fm.temporaryDirectory.appendingPathComponent("dir1", isDirectory: true)
    let targetDir = tempDir.appendingPathComponent("junkDir", isDirectory: true)
    XCTAssertFalse(fm.fileExists(atPath: targetDir.path))
    fm.changeCurrentDirectoryPath(tempDir.path)
    
    if case .success = ash.command(command: "rmdir; junkDir") {
      XCTAssert(false)
    }
  }

  func testRmDirOnFile() {
    let tempDir = fm.temporaryDirectory.appendingPathComponent("dir1", isDirectory: true)
    let targetDir = tempDir.appendingPathComponent("junkDir", isDirectory: true)
    let targetFile = targetDir.appendingPathComponent("junkFile", isDirectory: true)
    try! fm.createDirectory(at: targetDir, withIntermediateDirectories: true, attributes: nil)
    fm.createFile(atPath: targetFile.path, contents: "just some junk".data(using: .utf8), attributes: nil)
    XCTAssert(fm.fileExists(atPath: targetFile.path))
    fm.changeCurrentDirectoryPath(targetDir.path)
    
    if case .success = ash.command(command: "rmdir; junkDir") {
      XCTAssert(false)
    }
    try! fm.removeItem(at: targetDir)
  }

  func testPs() throws {
    // Not really sure how to test this other than to assure we get a value back, not sure what could force a failure
    let command = try XCTUnwrap(Command("ps; it; shouldn't; matter what; goes; here"))
    XCTAssertEqual(command.command, .ps)

    switch ash.command(command: "ps; it; shouldn't; matter what; goes; here") {
    case .success: XCTAssert(true)
    case .failure(let error): XCTAssert(false, error.localizedDescription)
    }
  }
  
  func testCat() throws {
    let command = try XCTUnwrap(Command("cat; testFile"))
    XCTAssertEqual(command.command, .cat)
    XCTAssertEqual(command.filePath, "testFile")

    let tempDir = fm.temporaryDirectory.appendingPathComponent("dir1", isDirectory: true)
    fm.changeCurrentDirectoryPath(tempDir.path)

    switch ash.command(command: "cat; subdir1/file3") {
    case .success(.string(let contents)): XCTAssert(contents == "I am file 3!")
    case .success(let what): XCTAssert(false, "TF? \(what)")
    case .failure(let error): XCTAssert(false, error.localizedDescription)
    }
  }
  
  func testCatMultiple() {
    let tempDir = fm.temporaryDirectory.appendingPathComponent("dir1", isDirectory: true)
    fm.changeCurrentDirectoryPath(tempDir.path)

    switch ash.command(command: "cat; file1; file2; subdir1/file3") {
    case .success(.string(let contents)): XCTAssert(contents == "I am file 1!\nI am file 2!\nI am file 3!")
    case .success(let what): XCTAssert(false, "TF? \(what)")
    case .failure(let error): XCTAssert(false, "\(error)")
    }
  }
  
  func testCatNonexistent() {
    let tempDir = fm.temporaryDirectory.appendingPathComponent("dir1", isDirectory: true)
    fm.changeCurrentDirectoryPath(tempDir.path)

    if case .success = ash.command(command: "cat; snapplejacks") {
      XCTAssert(false)
    }
  }

  func testCatNoPermissions() {
    let tempDir = fm.temporaryDirectory.appendingPathComponent("dir1", isDirectory: true)
    fm.changeCurrentDirectoryPath(tempDir.path)
    let unreadible = tempDir.appendingPathComponent("unreadible")
    defer {
      try! fm.removeItem(at: unreadible)
    }
    fm.createFile(atPath: unreadible.path, contents: "You can't read me!".data(using: .utf8), attributes: [.posixPermissions: 0o200])

    XCTAssertFalse(fm.isReadableFile(atPath: unreadible.path))
    if case .success = ash.command(command: "cat; snapplejacks") {
      XCTAssert(false)
    }
  }
  
  func testMv() throws {
    let command = try XCTUnwrap(Command("mv; testFile; testFile2"))
    XCTAssertEqual(command.command, .mv)
    XCTAssertEqual(command.arguments, ["testFile", "testFile2"])

    let tempDir = fm.temporaryDirectory.appendingPathComponent("dir1", isDirectory: true)
    fm.changeCurrentDirectoryPath(tempDir.path)

    let file6Path = tempDir.appendingPathComponent("file6").path
    switch ash.command(command: "mv; file1; file6") {
    case .success(_):
      XCTAssert(fm.fileExists(atPath: file6Path), "file6 should exist at \(tempDir.path)")
      XCTAssert(try String(contentsOfFile: file6Path, encoding: .utf8) == "I am file 1!", "file6 contents incorrect")
      let _ = ash.command(command: "mv; file6; file1")
    case .failure(let error): XCTAssert(false, error.localizedDescription)
    }
  }

  func testMvMultiple() throws {
    let tempDir = fm.temporaryDirectory.appendingPathComponent("dir1", isDirectory: true)
    let subDir = tempDir.appendingPathComponent("subdir1", isDirectory: true)
    fm.changeCurrentDirectoryPath(tempDir.path)

    let file1Path = subDir.appendingPathComponent("file1").path
    let file2Path = subDir.appendingPathComponent("file2").path
    switch ash.command(command: "mv; file1; file2; subdir1") {
    case .success(_):
      XCTAssert(fm.fileExists(atPath: file1Path), "file1 should exist at \(subDir.path)")
      XCTAssert(fm.fileExists(atPath: file2Path), "file2 should exist at \(subDir.path)")
      XCTAssert(try String(contentsOfFile: file1Path, encoding: .utf8) == "I am file 1!", "file1 contents incorrect")
      XCTAssert(try String(contentsOfFile: file2Path, encoding: .utf8) == "I am file 2!", "file2 contents incorrect")
      if case let .failure(error) = ash.command(command: "mv; subdir1/file1; .") { XCTFail("Could not move file1 back: \(error)") }
      if case let .failure(error) = ash.command(command: "mv; subdir1/file2; file2") { XCTFail("Could not move file2 back: \(error)") }
    case .failure(let error): XCTAssert(false, error.localizedDescription)
    }
  }

  func testCp() throws {
    let command = try XCTUnwrap(Command("cp; testFile; testFile2"))
    XCTAssertEqual(command.command, .cp)
    XCTAssertEqual(command.arguments, ["testFile", "testFile2"])

    let tempDir = fm.temporaryDirectory.appendingPathComponent("dir1", isDirectory: true)
    fm.changeCurrentDirectoryPath(tempDir.path)

    let file1Path = tempDir.appendingPathComponent("file1").path
    let file6Path = tempDir.appendingPathComponent("file6").path
    switch ash.command(command: "cp; file1; file6") {
    case .success(_):
      XCTAssert(fm.fileExists(atPath: file1Path), "file1 should exist at \(tempDir.path)")
      XCTAssert(fm.fileExists(atPath: file6Path), "file6 should exist at \(tempDir.path)")
      XCTAssert(try String(contentsOfFile: file6Path, encoding: .utf8) == "I am file 1!", "file6 contents incorrect")
      try! fm.removeItem(atPath: file6Path)
    case .failure(let error): XCTAssert(false, error.localizedDescription)
    }
  }

  func testCpMultiple() throws {
    let tempDir = fm.temporaryDirectory.appendingPathComponent("dir1", isDirectory: true)
    let subDir = tempDir.appendingPathComponent("subdir1", isDirectory: true)
    fm.changeCurrentDirectoryPath(tempDir.path)

    let file1Path = subDir.appendingPathComponent("file1").path
    let file2Path = subDir.appendingPathComponent("file2").path
    switch ash.command(command: "cp; file1; file2; subdir1") {
    case .success(_):
      XCTAssert(fm.fileExists(atPath: tempDir.appendingPathComponent("file1").path), "file1 should exist at \(tempDir.path)")
      XCTAssert(fm.fileExists(atPath: file1Path), "file1 should exist at \(subDir.path)")
      XCTAssert(fm.fileExists(atPath: tempDir.appendingPathComponent("file2").path), "file2 should exist at \(tempDir.path)")
      XCTAssert(fm.fileExists(atPath: file2Path), "file2 should exist at \(subDir.path)")
      XCTAssert(try String(contentsOfFile: file1Path, encoding: .utf8) == "I am file 1!", "file1 contents incorrect")
      XCTAssert(try String(contentsOfFile: file2Path, encoding: .utf8) == "I am file 2!", "file2 contents incorrect")
      try! fm.removeItem(atPath: file1Path)
      try! fm.removeItem(atPath: file2Path)
    case .failure(let error): XCTAssert(false, error.localizedDescription)
    }
  }
  
  func testMan() throws {
    let command = try XCTUnwrap(Command("man; should be; ignored"))
    XCTAssertEqual(command.command, .man)
    
    let expectedResult = """
                    The following are commands ran as API calls:
                    mkdir; --- Make a directory.
                    whoami; --- Print the current user.
                    cd; --- Change directories.
                    ls; --- List the directory.
                    ps; --- Will list all processes not limited to user processes.
                    cat; --- This will print the contents of a file.
                    mv; --- Perform a mv command to move files/folders.
                    cp; --- Copy a file/folder.
                    screenshot; <Destination> --- Take a snapshot of all screens. This will notify the user.
                    osascript; <Code> --- This will run an Apple script.
                    exfil; <binary> --- Will grab the raw data of a file.
                    execute; <App to Run> --- This will execute an application (no shell needed).
                    shell; <shell command> --- Runs a command in zsh. Equivalent of `zsh -c 'shell command'`
                    """
    
    switch ash.command(command: "man;") {
    case .success(.string(let manPage)):
      XCTAssertEqual(manPage, expectedResult)
    case .success, .failure: XCTFail()
    }
  }

  func testExfil() throws {
    let command = try XCTUnwrap(Command("exfil; file2"))
    XCTAssertEqual(command.command, .exfil)
    XCTAssertEqual(command.arguments, ["file2"])
    
    let tempDir = fm.temporaryDirectory.appendingPathComponent("dir1", isDirectory: true)
    fm.changeCurrentDirectoryPath(tempDir.path)
    switch ash.command(command: "exfil; file2") {
    case let .success(.data(data)):
          XCTAssertEqual(
            data,
            "I am file 2!".data(using: .utf8),
            "File contents incorrect: \(String(data: data, encoding: .utf8) ?? "LOL, wut?")"
          )
    case .success:
      XCTFail("Iunno…? LOL!")
    case .failure(let error):
      XCTFail("\(error)")
    }
  }
   
  func testShell() throws {
    let command = try XCTUnwrap(Command("shell; ls; -la"))
    XCTAssertEqual(command.command, .shell)
    XCTAssertEqual(command.arguments, ["ls", "-la"])
    
    // Note: this command does not work -- 'say' executes but the process does not terminate for unknown reasons
    // need to figure this out
//    switch ash.command(command: "shell; /usr/bin/say \"hello world\"") {
    if case let .failure(error) = ash.command(command: "shell; ls; -la") {
      XCTFail("\(error)")
    }
  }

  #if os(macOS)
    func testExecute() throws {
      let command = try XCTUnwrap(Command("execute; /System/Applications/Calculator.app"))
      XCTAssertEqual(command.command, .execute)
      XCTAssertEqual(command.arguments, ["/System/Applications/Calculator.app"])
      
      // Calculator should pop up
      if case let .failure(error) = ash.command(command: "execute; /System/Applications/Calculator.app") {
        XCTFail(error.localizedDescription)
      }
    }
    
    func testExecuteNonexistent() {
      switch ash.command(command: "execute; /System/Applications/ThisAppDoesNoteExist.app") {
      case .success(.string(let cmdMessage)):
        XCTFail(cmdMessage)
      case .success: XCTFail("Iunno…? LOL!")
      case .failure(let error):
        XCTAssertEqual(error.localizedDescription, "The application “ThisAppDoesNoteExist.app” could not be launched because it was not found.")
      }
    }
    
  func testScreenshot() throws {
    let command = try XCTUnwrap(Command("screenshot;"))
    XCTAssertEqual(command.command, .screenshot)

    switch ash.command(command: "screenshot;") {
    case let .success(.screenshots(timestamp: _, screenshots: shotData)):
      guard let shot = shotData.first else { XCTFail("Screenshot array empty"); return  }
      let pngHeader = Data([0x89, 0x50, 0x4E, 0x47])
      XCTAssertEqual(shot.prefix(4), pngHeader)
//      let tmpFile = fm.temporaryDirectory.appendingPathComponent("shot.png")
//      try shot.write(to: tmpFile)
//      print("Wrote to \(tmpFile.path)")
    case .success:
      XCTFail("Iunno…? LOL!")
    case .failure(let error):
      XCTFail("\(error)")
    }
  }
  
  func testOSAScript() throws {
    let command = try XCTUnwrap(Command("osascript; tell application \"Calculator\" activate end tell"))
    XCTAssertEqual(command.command, .osascript)
    XCTAssertEqual(command.arguments, ["tell application \"Calculator\" activate end tell"])
    
    // Should pop calc
    switch ash.command(command: "osascript; tell application \"Calculator\"\n activate\nend tell") {
    case .success(.string(_)):
          XCTAssert(true)
    case .success:
      XCTFail("Iunno…? LOL!")
    case .failure(let error):
      XCTFail("\(error)")
    }
  }
  
  func testOSAScriptInteractive() throws {
    switch ash.command(command: "osascript; display dialog \"I am 1337!!1!\"") {
    case .success(.string(let message)):
          XCTFail("Unexpected success: \(message)")
    case .success:
      XCTFail("Iunno…? LOL!")
    case .failure(let error):
      XCTAssert("\(error)".contains("No user interaction allowed."))
    }
  }
  #endif

  #if os(macOS)
    static var allTests = [
      ("testLs", testLs),
      ("testLsEmpty", testLsEmpty),
      ("testCd", testCd),
      ("testCdRelative", testCdRelative),
      ("testCdFailure", testCdFailure),
      ("testCdParent", testCdParent),
      ("testMkdir", testMkdir),
      ("testMkdirFailure", testMkdirFailure),
      ("testWhoami", testWhoami),
      ("testRm", testRm),
      ("testRmMultiple", testRmMultiple),
      ("testRmNonexistant", testRmNonexistant),
      ("testRmDir", testRmDir),
      ("testRmDirNonexistant", testRmDirNonexistant),
      ("testRmDirOnFile", testRmDirOnFile),
      ("testPs", testPs),
      ("testCat", testCat),
      ("testCatMultiple", testCatMultiple),
      ("testCatNonexistent", testCatNonexistent),
      ("testCatNoPermissions", testCatNoPermissions),
      ("testMv", testMv),
      ("testMvMultiple", testMvMultiple),
      ("testCp", testCp),
      ("testCpMultiple", testCpMultiple),
      ("testMan", testMan),
      ("testExfil", testExfil),
      ("testShell", testShell),
      ("testExecute", testExecute),
      ("testExecuteNonexistent", testExecuteNonexistent),
      ("testScreenshot", testScreenshot),
      ("testOSAScript", testOSAScript),
      ("testOSAScriptInteractive", testOSAScriptInteractive),
    ]
#else
    static var allTests = [
      ("testLs", testLs),
      ("testLsEmpty", testLsEmpty),
      ("testCd", testCd),
      ("testCdRelative", testCdRelative),
      ("testCdFailure", testCdFailure),
      ("testCdParent", testCdParent),
      ("testMkdir", testMkdir),
      ("testMkdirFailure", testMkdirFailure),
      ("testWhoami", testWhoami),
      ("testRm", testRm),
      ("testRmMultiple", testRmMultiple),
      ("testRmNonexistant", testRmNonexistant),
      ("testRmDir", testRmDir),
      ("testRmDirNonexistant", testRmDirNonexistant),
      ("testRmDirOnFile", testRmDirOnFile),
      ("testPs", testPs),
      ("testCat", testCat),
      ("testCatMultiple", testCatMultiple),
      ("testCatNonexistent", testCatNonexistent),
      ("testCatNoPermissions", testCatNoPermissions),
      ("testMv", testMv),
      ("testMvMultiple", testMvMultiple),
      ("testCp", testCp),
      ("testCpMultiple", testCpMultiple),
      ("testMan", testMan),
      ("testExfil", testExfil),
      ("testShell", testShell),
      ("testExecute", testExecute),
      ("testExecuteNonexistent", testExecuteNonexistent),
      ("testScreenshot", testScreenshot),
      ("testOSAScript", testOSAScript),
      ("testOSAScriptInteractive", testOSAScriptInteractive),
    ]
#endif
}
