import PerfectNet
import Foundation
#if os(Linux)
import Glibc
#endif
import PerfectCRUD
import PerfectCrypto
import SwiftCodables
import SAuthCodables
import PerfectNotifications
import PerfectThread

extension String {
  public func tear(_ by: Character) -> (String, String) {
    let blocks = self.split(separator: by)
    guard blocks.count > 1 else {
      return (self, "")
    }
    let first = String(blocks[0])
    let remain = blocks.dropFirst().joined(separator: String(by))
    return (first, remain)
  }
}

public struct IRCPrivateMessage {
  public let nickname: String
  public let realname: String
  public let address: String
  public let channel: String
  public let content: String

  public init?(by: String) {
    guard by.hasPrefix(":") else { return nil }
    let a = String(by.dropFirst())
    let b = a.tear("!")
    nickname = b.0
    let c = b.1.tear("@")
    realname = c.0
    let d = c.1.tear("#")
    guard d.0.contains("PRIVMSG") else { return nil }
    let e = d.0.split(separator: " ").map { String($0) }
    guard let f = e.first else { return nil }
    address = f
    let g = d.1.tear(":")
    channel = g.0.trimmingCharacters(in: CharacterSet.init(charactersIn: " \t\r\n"))
    content = g.1
  }
}

public class IRCClient {

  public enum Exception: Error {
    case connectionFailure
    case loginFailure
    case nothingReceived
    case invalidEncoding
  }
  public let lock = DispatchSemaphore.init(value: 0)
  public let queue: DispatchQueue
  private var live = true

  public static var `default`: IRCClient? = nil

  let net = NetTCPSSL()

  public var channels: Set<String> = []

  public typealias MessageEvent = (IRCPrivateMessage) -> Void

  public let onMessage: MessageEvent = { message in
    do {
      let db = try biqDatabaseInfo.deviceDb()
      let deviceOwners = db.table(BiqDevice.self).where(\BiqDevice.id == message.channel)
      let permission = db.table(BiqDeviceAccessPermission.self).where(\BiqDeviceAccessPermission.deviceId == message.channel)
      let perm = try permission.select()
      let owners = try deviceOwners.select()
      let adb = try biqDatabaseInfo.authDb()
      let aliasTable = try adb.table(AliasBrief.self).select()
      let mobileTable = try adb.table(MobileDeviceId.self).select()
      let biqId = message.channel
      var biqName = ""
      let uid:Set<String> = try db.transaction { () -> Set<String> in
        let u1 = perm.map { $0.userId.uuidString }
        let u2 = owners.map { $0.ownerId?.uuidString ?? "" }.filter { !$0.isEmpty }
        let names = owners.map { $0.name }
        if let name = names.first {
          biqName = name
        }
        return Set<String>(u1 + u2)
      }

      let lowered = message.nickname.lowercased()
      let sql = "SELECT * FROM account WHERE id::text LIKE '\(lowered)%'"
      let fullName = try adb.transaction  { ()-> String? in
        let accounts = try adb.sql(sql, Account.self)
        let name = accounts.first?.meta?.fullName
        return name
      }
      // ignore non-qbiq channels
      guard !uid.isEmpty else { return }
      var recipient: [String] = []
      var speaker = fullName ?? message.realname
      try adb.transaction {
        uid.forEach { userId in
          if userId.hasPrefix(message.nickname) {
            return
          }
          let emails = aliasTable.filter { $0.account.uuidString == userId }.map { $0.address }
          let mobiles = mobileTable.filter { emails.contains($0.aliasId) }.map { $0.deviceId }
          recipient.append(contentsOf: mobiles)
        }
      }
      CRUDLogging.log(.info, "----------- FROM \(message.nickname)")
      CRUDLogging.log(.info, "----------- REAL \(message.realname)")
      CRUDLogging.log(.info, "----------- QBIQ \(message.channel)")
      CRUDLogging.log(.info, "----------- SPKR \(speaker)")
      CRUDLogging.log(.info, "----------- SURC \(biqName)")
      CRUDLogging.log(.info, "----------- CONT \(message.content)")
      guard !recipient.isEmpty else {
        CRUDLogging.log(.warning, "No recipients to notify")
        return
      }
      print("----------- RCPT ", recipient)
      NotificationPusher(apnsTopic: notificationsTopic).pushAPNS(
        configurationName: notificationsConfigName,
        deviceTokens: recipient,
        notificationItems: [
          .customPayload("qbiq.name", biqName),
          .customPayload("qbiq.id", biqId),
          .mutableContent,
          .category("qbiq.alert"),
          .threadId(biqId),
          .alertTitle("\(speaker)~ about \(biqName):"),
          .alertBody(message.content)]) { responses in
            CRUDLogging.log(.info, "----------- RESP \(responses)")
      }
    } catch(let err) {
      CRUDLogging.log(.warning, "Notification Sending: \(err)")
    }

  }
  
  public func run(_ onMessage: @escaping MessageEvent) {
    queue.async {
      while self.live {
        var buf:[UInt8]? = nil
        self.net.readSomeBytes(count: 4096) {
          buffer in
          buf = buffer
          self.lock.signal()
        }
        self.lock.wait()
        guard let content = buf else {
          self.live = false
          break
        }
        if !content.isEmpty, let line = String(validatingUTF8: content) {
          if line.hasPrefix("PING") {
            let reply = line.replacingOccurrences(of: "PING", with: "PONG")
            self.net.write(string: reply) { _ in }
          } else {
            guard let msg = IRCPrivateMessage(by: line) else {
              print("none private message: ", line)
              continue
            }
            onMessage(msg)
          }
        } else {
          sleep(1)
        }
      }
    }
  }

  public func join() {
    print("channels found:", self.channels)
    let topics = self.channels.map { "JOIN #\($0)\r" }
    let command = topics.joined(separator: "\n") + "\n"
    self.net.write(string: command) { _ in }
  }

  public func scanChannels() -> Set<String>? {
    guard let db = try? biqDatabaseInfo.deviceDb() else {
      CRUDLogging.log(.warning, "deviceDB() failure")
      return nil
    }
    let devices = db.table(BiqDevice.self)
    guard let dev = try? devices.select() else {
      CRUDLogging.log(.warning, "BiqDevice table failure")
      return nil
    }
    guard let topics = (try? db.transaction { () -> [String] in
      let topics:[String] = dev.map { $0.id }
      return topics
      }) else {
        CRUDLogging.log(.warning, "channel scan failure")
        return nil
    }
    return Set<String>(topics)
  }

  public func runChannels() {
    guard let cnn = self.scanChannels() else {
      CRUDLogging.log(.warning, "channel scan failure")
      return
    }
    self.channels = cnn
    self.join()

    let channelWorks = DispatchQueue.init(label: UUID.init().uuidString)
    channelWorks.async {
      while self.live {
        guard let scan = self.scanChannels() else {
          CRUDLogging.log(.warning, "channel scan failure")
          break
        }
        guard scan == self.channels else {
          self.channels = scan
          self.join()
          continue
        }
        sleep(30)
      }
      CRUDLogging.log(.warning, "channel service is over")
    }
  }

  public init(host: String, port: Int, nick: String, pass: String,
              completion: @escaping (Error?) -> Void) {
    do {
      queue = DispatchQueue.init(label: "\(host)_\(port)")
      try net.connect(address: host, port: UInt16(port), timeoutSeconds: 5.0) {
        net in
        guard let ssl = net as? NetTCPSSL else {
          self.lock.signal()
          completion(Exception.connectionFailure)
          return
        }
        let loginStr =
        """
        PASS \(pass)
        NICK \(nick)
        USER \(nick) \(host) \(host) \(nick)

        """
        print("logging as ", loginStr)
        ssl.write(string: loginStr) { written in
          guard written > 0 else {
            self.lock.signal()
            completion(Exception.loginFailure)
            return
          }
          self.lock.signal()
          completion(nil)
        }
      }
    } catch (let err) {
      self.lock.signal()
      completion(err)
    }
  }
}
