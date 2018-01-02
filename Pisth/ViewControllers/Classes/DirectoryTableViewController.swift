// This source file is part of the https://github.com/ColdGrub1384/Pisth open source project
//
// Copyright (c) 2017 - 2018 Adrian Labbé
// Licensed under Apache License v2.0
//
// See https://raw.githubusercontent.com/ColdGrub1384/Pisth/master/LICENSE for license information

import UIKit
import GoogleMobileAds

class DirectoryTableViewController: UITableViewController, LocalDirectoryTableViewControllerDelegate, DirectoryTableViewControllerDelegate, GADBannerViewDelegate {
        
    var directory: String
    var connection: RemoteConnection
    var files: [String]?
    var isDir = [Bool]()
    var delegate: DirectoryTableViewControllerDelegate?
    var closeAfterSending = false
    var bannerView: GADBannerView!
    
    static var action = RemoteDirectoryAction.none
    
    static var disconnected = false
    
    init(connection: RemoteConnection, directory: String? = nil) {
        self.connection = connection
        ConnectionManager.shared.connection = connection
        
        if directory == nil {
            self.directory = connection.path
        } else {
            self.directory = directory!
        }
        
        var continue_ = false
        
        if !Reachability.isConnectedToNetwork() {
            continue_ = false
        } else if ConnectionManager.shared.filesSession == nil {
            continue_ = ConnectionManager.shared.connect()
        } else if !ConnectionManager.shared.filesSession!.isConnected || !ConnectionManager.shared.filesSession!.isAuthorized {
            continue_ = ConnectionManager.shared.connect()
        } else {
            continue_ = ConnectionManager.shared.filesSession!.isConnected && ConnectionManager.shared.filesSession!.isAuthorized
        }
        
        if continue_ {
            if self.directory == "~" { // Get absolute path from ~
                if let path = try? ConnectionManager.shared.filesSession?.channel.execute("echo $HOME").replacingOccurrences(of: "\n", with: "") {
                    self.directory = path!
                }
            }
            
            if let files = ConnectionManager.shared.files(inDirectory: self.directory) {
                self.files = files
                
                // Check if path is directory or not
                for file in files {
                    isDir.append(file.hasSuffix("/"))
                }
                
                if files == [self.directory+"/*"] { // The content of files is ["*"] when there is no file
                    self.files = []
                    isDir[isDir.count-1] = true
                }
                
                if self.directory.removingUnnecessariesSlashes != "/" {
                    self.files!.append(self.directory.nsString.deletingLastPathComponent) // Append parent directory
                    
                    isDir.append(true)
                }
            }
        }
        
        super.init(style: .plain)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let titleComponents = directory.components(separatedBy: "/")
        title = titleComponents.last
        if directory.hasSuffix("/") {
            title = titleComponents[titleComponents.count-2]
        }
        
        navigationItem.largeTitleDisplayMode = .never
        
        // TableView cells
        tableView.register(UINib(nibName: "FileTableViewCell", bundle: Bundle.main), forCellReuseIdentifier: "file")
        tableView.backgroundColor = .black
        clearsSelectionOnViewWillAppear = false
        tableView.tableFooterView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: 0))
        
        // Initialize the refresh control.
        refreshControl = UIRefreshControl()
        refreshControl?.tintColor = UIColor.white
        refreshControl?.addTarget(self, action: #selector(reload), for: .valueChanged)
        
        // Bar buttons
        let uploadFile = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(uploadFile(_:)))
        let terminal = UIBarButtonItem(image: #imageLiteral(resourceName: "terminal"), style: .plain, target: self, action: #selector(openShell))
        navigationItem.setRightBarButtonItems([uploadFile, terminal], animated: true)
        
        // Banner ad
        bannerView = GADBannerView(adSize: kGADAdSizeBanner)
        bannerView.rootViewController = self
        bannerView.adUnitID = "ca-app-pub-9214899206650515/4247056376"
        bannerView.delegate = self
        bannerView.load(GADRequest())
    }
    
    // MARK: - Actions
    
    @objc func close() {
        navigationController?.dismiss(animated: true, completion: nil)
    }
    
    @objc func reload() { // Reload current directory content
        files = nil
        isDir = []
        
        if let files = ConnectionManager.shared.files(inDirectory: self.directory) {
            self.files = files
            
            if files == [self.directory+"/*"] { // The content of files is ["*"] when there is no file
                self.files = []
            }
            
            // Check if path is directory or not
            for file in files {
                isDir.append(file.hasSuffix("/"))
            }
            
            if self.directory.removingUnnecessariesSlashes != "/" {
                self.files!.append(self.directory.nsString.deletingLastPathComponent) // Append parent directory
                isDir.append(true)
            }
        } else {
            self.files = nil
        }
        
        tableView.reloadData()
        refreshControl?.endRefreshing()
    }
    
    @objc func openShell() { // Open shell in current directory
        let terminalVC = Bundle.main.loadNibNamed("TerminalViewController", owner: nil, options: nil)!.first! as! TerminalViewController
        terminalVC.pwd = directory
        navigationController?.pushViewController(terminalVC, animated: true)
    }
    
    @objc func uploadFile(_ sender: UIBarButtonItem) { // Add file
        
        let chooseAlert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        chooseAlert.addAction(UIAlertAction(title: "Import", style: .default, handler: { (_) in // Upload file
            let localDirVC = LocalDirectoryTableViewController(directory: FileManager.default.documents)
            localDirVC.delegate = self
            
            self.navigationController?.pushViewController(localDirVC, animated: true)
        }))
        
        chooseAlert.addAction(UIAlertAction(title: "Create blank file", style: .default, handler: { (_) in // Create file
            
            let chooseName = UIAlertController(title: "Create blank file", message: "Choose new file name", preferredStyle: .alert)
            chooseName.addTextField(configurationHandler: { (textField) in
                textField.placeholder = "New file name"
            })
            chooseName.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            chooseName.addAction(UIAlertAction(title: "Create", style: .default, handler: { (_) in
                do {
                    let result = try ConnectionManager.shared.filesSession?.channel.execute("touch '\(self.directory)/\(chooseName.textFields![0].text!)' 2>&1")
                    
                    if result?.replacingOccurrences(of: "\n", with: "") != "" { // Error
                        let errorAlert = UIAlertController(title: nil, message: result, preferredStyle: .alert)
                        errorAlert.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
                        self.present(errorAlert, animated: true, completion: nil)
                    } else {
                        self.reload()
                    }
                } catch let error {
                    let errorAlert = UIAlertController(title: "Error creating file!", message: error.localizedDescription, preferredStyle: .alert)
                    errorAlert.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
                    self.present(errorAlert, animated: true, completion: nil)
                }
            }))
            
            self.present(chooseName, animated: true, completion: nil)
            
        }))
        
        chooseAlert.addAction(UIAlertAction(title: "Create folder", style: .default, handler: { (_) in // Create folder
            let chooseName = UIAlertController(title: "Create folder", message: "Choose new folder name", preferredStyle: .alert)
            chooseName.addTextField(configurationHandler: { (textField) in
                textField.placeholder = "New folder name"
            })
            chooseName.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            chooseName.addAction(UIAlertAction(title: "Create", style: .default, handler: { (_) in
                do {
                    let result = try ConnectionManager.shared.filesSession?.channel.execute("mkdir '\(self.directory)/\(chooseName.textFields![0].text!)' 2>&1")
                    
                    if result?.replacingOccurrences(of: "\n", with: "") != "" { // Error
                        let errorAlert = UIAlertController(title: nil, message: result, preferredStyle: .alert)
                        errorAlert.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
                        self.present(errorAlert, animated: true, completion: nil)
                    } else {
                        self.reload()
                    }
                } catch let error {
                    let errorAlert = UIAlertController(title: "Error creating folder!", message: error.localizedDescription, preferredStyle: .alert)
                    errorAlert.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
                    self.present(errorAlert, animated: true, completion: nil)
                }
            }))
            
            self.present(chooseName, animated: true, completion: nil)
        }))
        
        chooseAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        
        chooseAlert.popoverPresentationController?.barButtonItem = sender
        
        self.present(chooseAlert, animated: true, completion: nil)
    }
    
    @objc func copyFile() { // Copy file in current directory
        DirectoryTableViewController.action = .none
        navigationController?.dismiss(animated: true, completion: {
            do {
                let result = try ConnectionManager.shared.filesSession?.channel.execute("cp -R '\(Pasteboard.local.filePath!)' '\(self.directory)' 2>&1")
                
                if result?.replacingOccurrences(of: "\n", with: "") != "" { // Error
                    let errorAlert = UIAlertController(title: nil, message: result, preferredStyle: .alert)
                    errorAlert.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
                    UIApplication.shared.keyWindow?.rootViewController?.present(errorAlert, animated: true, completion: nil)
                }
                
                if let dirVC = (UIApplication.shared.keyWindow?.rootViewController as? UINavigationController)?.visibleViewController as? DirectoryTableViewController {
                    dirVC.reload()
                }
                
                Pasteboard.local.filePath = nil
            } catch let error {
                let errorAlert = UIAlertController(title: "Error copying file!", message: error.localizedDescription, preferredStyle: .alert)
                errorAlert.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
                UIApplication.shared.keyWindow?.rootViewController?.present(errorAlert, animated: true, completion: nil)
            }
        })
    }
    
    @objc func moveFile() { // Move file in current directory
        DirectoryTableViewController.action = .none
        navigationController?.dismiss(animated: true, completion: {
            do {
                let result = try ConnectionManager.shared.filesSession?.channel.execute("mv '\(Pasteboard.local.filePath!)' '\(self.directory)/\(Pasteboard.local.filePath!.nsString.lastPathComponent)' 2>&1")
                
                if result?.replacingOccurrences(of: "\n", with: "") != "" { // Error
                    let errorAlert = UIAlertController(title: nil, message: result, preferredStyle: .alert)
                    errorAlert.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
                    UIApplication.shared.keyWindow?.rootViewController?.present(errorAlert, animated: true, completion: nil)
                }
                
                if let dirVC = (UIApplication.shared.keyWindow?.rootViewController as? UINavigationController)?.visibleViewController as? DirectoryTableViewController {
                    dirVC.reload()
                }
                
                Pasteboard.local.filePath = nil
            } catch let error {
                let errorAlert = UIAlertController(title: "Error copying file!", message: error.localizedDescription, preferredStyle: .alert)
                errorAlert.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
                UIApplication.shared.keyWindow?.rootViewController?.present(errorAlert, animated: true, completion: nil)
            }
        })
    }
    
    // MARK: - Table view data source
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 87
    }
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        if let files = files {
            return files.count
        }
        
        return 0
    }
    
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "file") as! FileTableViewCell
        
        // Configure the cell...
        
        if let files = files {
            if files[indexPath.row] != directory.nsString.deletingLastPathComponent {
                if isDir[indexPath.row] {
                    let components = files[indexPath.row].components(separatedBy: "/")
                    cell.filename.text = components[components.count-2]
                } else {
                    cell.filename.text = files[indexPath.row].components(separatedBy: "/").last
                }
            } else {
                cell.filename.text = ".."
            }
        }
        
        if isDir.indices.contains(indexPath.row) {
            if isDir[indexPath.row] {
                cell.iconView.image = #imageLiteral(resourceName: "folder")
            } else if files![indexPath.row].hasPrefix("./") {
                cell.iconView.image = #imageLiteral(resourceName: "bin")
            } else {
                cell.iconView.image = fileIcon(forExtension: files![indexPath.row].nsString.pathExtension)
            }
        }
        
        return cell
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // Remove file
            do {
                let result = try ConnectionManager.shared.filesSession?.channel.execute("rm -rf '\(files![indexPath.row])' 2>&1")
                
                if result?.replacingOccurrences(of: "\n", with: "") != "" { // Error
                    let errorAlert = UIAlertController(title: nil, message: result, preferredStyle: .alert)
                    errorAlert.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
                    self.present(errorAlert, animated: true, completion: nil)
                } else {
                    files!.remove(at: indexPath.row)
                    isDir.remove(at: indexPath.row)
                    tableView.deleteRows(at: [indexPath], with: .fade)
                }
            } catch let error {
                let errorAlert = UIAlertController(title: "Error removing file!", message: error.localizedDescription, preferredStyle: .alert)
                errorAlert.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
                self.present(errorAlert, animated: true, completion: nil)
            }
        }
    }
    
    override func tableView(_ tableView: UITableView, canPerformAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?) -> Bool {
        return (action == #selector(UIResponderStandardEditActions.copy(_:))) // Enable copy
    }
    
    override func tableView(_ tableView: UITableView, shouldShowMenuForRowAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    override func tableView(_ tableView: UITableView, performAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?) {
        if action == #selector(copy(_:)) { // Copy file
            
            Pasteboard.local.filePath = files![indexPath.row]
            
            let dirVC = DirectoryTableViewController(connection: connection, directory: directory)
            dirVC.navigationItem.prompt = "Select a directory where copy file"
            dirVC.delegate = dirVC
            DirectoryTableViewController.action = .copyFile
            
            
            let navVC = UINavigationController(rootViewController: dirVC)
            navVC.navigationBar.barStyle = .black
            navVC.navigationBar.isTranslucent = true
            present(navVC, animated: true, completion: {
                dirVC.navigationItem.setRightBarButtonItems([UIBarButtonItem(title: "Copy here", style: .plain, target: dirVC, action: #selector(dirVC.copyFile))], animated: true)
                dirVC.navigationItem.setLeftBarButtonItems([UIBarButtonItem(title: "Done", style: .done, target: dirVC, action: #selector(dirVC.close))], animated: true)
            })
        }
    }
    
    // MARK: - Table view delegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        guard let cell = tableView.cellForRow(at: indexPath) as? FileTableViewCell else { return }
        
        var continueDownload = true
        
        if cell.iconView.image == #imageLiteral(resourceName: "folder") { // Open folder
            
            let activityVC = ActivityViewController(message: "Loading")
            self.present(activityVC, animated: true, completion: {
                let dirVC = DirectoryTableViewController(connection: self.connection, directory: self.files?[indexPath.row].removingUnnecessariesSlashes)
                if let delegate = self.delegate {
                    activityVC.dismiss(animated: true, completion: {
                        
                        delegate.directoryTableViewController(dirVC, didOpenDirectory: self.files![indexPath.row])
                        
                        tableView.deselectRow(at: indexPath, animated: true)
                    })
                } else {
                    activityVC.dismiss(animated: true, completion: {
                        
                        self.navigationController?.pushViewController(dirVC, animated: true)
                        
                        tableView.deselectRow(at: indexPath, animated: true)
                    })
                }
            })
        } else if cell.iconView.image == #imageLiteral(resourceName: "bin") { // Execute file
            
            let activityVC = ActivityViewController(message: "Loading")
            
            self.present(activityVC, animated: true, completion: {
                let terminalVC = Bundle.main.loadNibNamed("TerminalViewController", owner: nil, options: nil)!.first! as! TerminalViewController
                terminalVC.command = "'\(String(self.files![indexPath.row].removingUnnecessariesSlashes.dropFirst()))'"
                terminalVC.pwd = self.directory
                
                activityVC.dismiss(animated: true, completion: {
                    self.navigationController?.pushViewController(terminalVC, animated: true)
                })
            })
        } else { // Download file
            
            let activityVC = UIAlertController(title: "Downloading...", message: "", preferredStyle: .alert)
            activityVC.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { (_) in
                continueDownload = false
                tableView.deselectRow(at: indexPath, animated: true)
            }))
            
            self.present(activityVC, animated: true, completion: {
                guard let session = ConnectionManager.shared.filesSession else {
                    tableView.deselectRow(at: indexPath, animated: true)
                    activityVC.dismiss(animated: true, completion: nil)
                    DirectoryTableViewController.disconnected = true
                    self.navigationController?.popToRootViewController(animated: true)
                    return
                }
                
                if !Reachability.isConnectedToNetwork() {
                    tableView.deselectRow(at: indexPath, animated: true)
                    activityVC.dismiss(animated: true, completion: nil)
                    DirectoryTableViewController.disconnected = true
                    self.navigationController?.popToRootViewController(animated: true)
                    return
                }
                
                if !session.isConnected || !session.isAuthorized {
                    tableView.deselectRow(at: indexPath, animated: true)
                    activityVC.dismiss(animated: true, completion: nil)
                    DirectoryTableViewController.disconnected = true
                    self.navigationController?.popToRootViewController(animated: true)
                    return
                }
                
                let newFile = FileManager.default.documents.appendingPathComponent(cell.filename.text!)
                
                DispatchQueue.global(qos: .background).async {
                    if let data = session.sftp.contents(atPath: self.files![indexPath.row].removingUnnecessariesSlashes, progress: { (receivedBytes, bytesToBeReceived) -> Bool in
                        
                        let received = ByteCountFormatter().string(fromByteCount: Int64(receivedBytes))
                        let toBeReceived = ByteCountFormatter().string(fromByteCount: Int64(bytesToBeReceived))
                        
                        DispatchQueue.main.async {
                            activityVC.message = "\(received) / \(toBeReceived)"
                        }
                        
                        return continueDownload
                    }) {
                        DispatchQueue.main.async {
                            do {
                                try data.write(to: newFile)
                                
                                activityVC.dismiss(animated: true, completion: {
                                    ConnectionManager.shared.saveFile = SaveFile(localFile: newFile.path, remoteFile: self.files![indexPath.row])
                                    LocalDirectoryTableViewController.openFile(newFile, from: tableView.cellForRow(at: indexPath)!.frame, in: tableView, navigationController: self.navigationController, showActivityViewControllerInside: self)
                                })
                            } catch let error {
                                activityVC.dismiss(animated: true, completion: {
                                    let errorAlert = UIAlertController(title: "Error downloading file!", message: error.localizedDescription, preferredStyle: .alert)
                                    errorAlert.addAction(UIAlertAction(title: "Ok", style: .default, handler: nil))
                                    self.present(errorAlert, animated: true, completion: nil)
                                })
                            }
                            
                            tableView.deselectRow(at: indexPath, animated: true)
                        }
                    } else {
                        DispatchQueue.main.async {
                            activityVC.dismiss(animated: true, completion: {
                                self.navigationController?.popToRootViewController(animated: true)
                            })
                        }
                    }
                }
            })
        }
                
    }
    
    // MARK: - LocalDirectoryTableViewControllerDelegate
    
    func localDirectoryTableViewController(_ localDirectoryTableViewController: LocalDirectoryTableViewController, didOpenFile file: URL) { // Send file
        
        // Upload file
        func sendFile() {
            
            let activityVC = ActivityViewController(message: "Uploading")
            self.present(activityVC, animated: true) {
                do {
                    let dataToSend = try Data(contentsOf: file)
                    
                    ConnectionManager.shared.filesSession?.sftp.writeContents(dataToSend, toFileAtPath: self.directory.nsString.appendingPathComponent(file.lastPathComponent))
                    
                    if self.closeAfterSending {
                        activityVC.dismiss(animated: true, completion: {
                            AppDelegate.shared.close()
                        })
                    } else {
                        activityVC.dismiss(animated: true, completion: {
                            self.reload()
                        })
                    }
                    
                } catch let error {
                    let errorAlert = UIAlertController(title: "Error reading file data!", message: error.localizedDescription, preferredStyle: .alert)
                    errorAlert.addAction(UIAlertAction(title: "Ok", style: .cancel, handler: nil))
                    self.present(errorAlert, animated: true, completion: nil)
                }
            }
        }
        
        // Ask user to send file
        let confirmAlert = UIAlertController(title: file.lastPathComponent, message: "Do you want to send \(file.lastPathComponent) to \(directory.nsString.lastPathComponent)?", preferredStyle: .alert)
        
        confirmAlert.addAction(UIAlertAction(title: "No", style: .cancel, handler: nil))
        
        confirmAlert.addAction(UIAlertAction(title: "Yes", style: .default, handler: { (action) in
            sendFile()
        }))
        
        // Go back here
        navigationController?.popToViewController(self, animated: true, completion: {
            self.present(confirmAlert, animated: true, completion: nil)
        })
    }
    
    // MARK: - DirectoryTableViewControllerDelegate
    
    func directoryTableViewController(_ directoryTableViewController: DirectoryTableViewController, didOpenDirectory directory: String) {
        directoryTableViewController.delegate = directoryTableViewController
        
        if DirectoryTableViewController.action == .copyFile {
            directoryTableViewController.navigationItem.prompt = "Select a directory where copy file"
        }
        
        if DirectoryTableViewController.action == .moveFile {
            directoryTableViewController.navigationItem.prompt = "Select a directory where move file"
        }
        
        navigationController?.pushViewController(directoryTableViewController, animated: true, completion: {
            if DirectoryTableViewController.action == .copyFile {
                directoryTableViewController.navigationItem.setRightBarButtonItems([UIBarButtonItem(title: "Copy here", style: .plain, target: directoryTableViewController, action: #selector(directoryTableViewController.copyFile))], animated: true)
            }
            
            if DirectoryTableViewController.action == .moveFile {
                directoryTableViewController.navigationItem.setRightBarButtonItems([UIBarButtonItem(title: "Move here", style: .plain, target: directoryTableViewController, action: #selector(directoryTableViewController.moveFile))], animated: true)
            }
        })
    }
    
    // MARK: - GADBannerViewDelegate
    
    func adViewDidReceiveAd(_ bannerView: GADBannerView) {
        // Show ad only when it received
        tableView.tableHeaderView = bannerView
    }
}
