//
//  ProfileHandlers.swift
//  BiqServer
//
//  Created by Rocky Wei on 2019-01-07.
//
import PerfectLib
import PerfectNet
import Foundation
import PerfectCRUD
import PerfectCrypto
import SwiftCodables
import SAuthCodables
import PerfectNotifications
import PerfectThread
import PerfectHTTP

public struct ProfileAPIResponse: Codable {
  public var content = ""
}

public struct ProfileHandlers {

  static let sizeLimitationImage = 1048576
  static let sizeLimitationText = 65536

  static func imgPath(uid: String) -> String {
    return "profiles/\(uid).json"
  }

  static func txtPath(uid: String) -> String {
    return "profiles/\(uid).txt"
  }

  static func identity(session rs: RequestSession) throws -> RequestSession {
    return rs
  }

  static func uploadImage(session rs: RequestSession) throws -> ProfileAPIResponse {
    let uid = rs.session.id.uuidString.lowercased()
    guard let bytes = rs.request.postBodyBytes else {
      return ProfileAPIResponse.init(content: "empty")
    }
    let data = Data.init(bytes: bytes)
    let prof = try JSONDecoder.init().decode(ProfileAPIResponse.self, from: data)
    let text = prof.content
    guard text.count < sizeLimitationImage else {
      return ProfileAPIResponse.init(content: "oversized")
    }
    let file = File.init(ProfileHandlers.imgPath(uid: uid))
    try file.open(.truncate)
    let count = try file.write(string: text)
    file.close()
    return ProfileAPIResponse.init(content: "\(count)")
  }

  static func downloadImage(session rs: RequestSession) throws -> ProfileAPIResponse {
    guard let uid = rs.request.param(name: "uid") else {
      return ProfileAPIResponse.init()
    }
    let file = File.init(ProfileHandlers.imgPath(uid: uid))
    try file.open(.read)
    let text = try file.readString()
    file.close()
    return ProfileAPIResponse.init(content: text)
  }

  static func uploadText(session rs: RequestSession) throws -> ProfileAPIResponse {
    let uid = rs.session.id.uuidString.lowercased()
    guard let bytes = rs.request.postBodyBytes else {
      return ProfileAPIResponse.init(content: "empty")
    }
    let data = Data.init(bytes: bytes)
    let prof = try JSONDecoder.init().decode(ProfileAPIResponse.self, from: data)
    let text = prof.content
    guard text.count < sizeLimitationText else {
      return ProfileAPIResponse.init(content: "oversized")
    }
    let file = File.init(ProfileHandlers.txtPath(uid: uid))
    try file.open(.truncate)
    let count = try file.write(string: text)
    file.close()
    return ProfileAPIResponse.init(content: "\(count)")
  }

  static func downloadText(session rs: RequestSession) throws -> ProfileAPIResponse {
    guard let uid = rs.request.param(name: "uid") else {
      return ProfileAPIResponse.init()
    }
    let file = File.init(ProfileHandlers.txtPath(uid: uid))
    try file.open(.read)
    let text = try file.readString()
    file.close()
    return ProfileAPIResponse.init(content: text)
  }

  static func userFullName(session rs: RequestSession) throws -> ProfileAPIResponse {
    let adb = try biqDatabaseInfo.authDb()
    guard let uid = rs.request.param(name: "uid"),
      let guest = Foundation.UUID.init(uuidString: uid),
      let account = (try adb.table(Account.self).where(\Account.id == guest).first()),
      let fullName = account.meta?.fullName else {
        return ProfileAPIResponse.init()
    }
    return ProfileAPIResponse.init(content: fullName)
  }

  static func validate(session rs: RequestSession) throws -> [IAPReceiptAgent.ReceiptItem] {
    guard let postbody = rs.request.postBodyString,
      !biqIAPSecret.isEmpty else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid request.")
    }
    guard let agentPro = IAPReceiptAgent.init(base64EncodedReceipt: postbody, password: biqIAPSecret),
      let agentSandbox = IAPReceiptAgent.init(base64EncodedReceipt: postbody, password: biqIAPSecret, sandbox: true) else {
				throw HTTPResponseError(status: .badRequest, description: "Unable to initialize.")
    }
    let receipts = try agentPro.syncValidate()
    if receipts.isEmpty {
      return try agentSandbox.syncValidate()
    } else {
      return receipts
    }
  }
}


public class IAPReceiptAgent {

  public struct ReceiptItem: Codable {
    public let product_id: String
    public let purchase_date_ms: String
    public let expires_date_ms: String
  }

  public struct Receipt: Codable {
    public let latest_receipt_info: [ReceiptItem]
  }

  private let _request: URLRequest
  private let lock = DispatchSemaphore.init(value: 1)

  public init?(base64EncodedReceipt: String, password: String, sandbox: Bool = false) {
    let postBody = "{\"receipt-data\":\"\(base64EncodedReceipt)\", \"password\":\"\(password)\"}"
    let prefix = sandbox ? "sandbox": "buy"
    guard let appStoreURL = URL.init(string: "https://\(prefix).itunes.apple.com/verifyReceipt")
      else {
        return nil
    }
    let bytes: [UInt8] = postBody.utf8.map { $0 }
    var request = URLRequest.init(url: appStoreURL)
    request.httpMethod = "POST"
    request.httpBody = Data.init(bytes: bytes)
    _request = request
  }

  public func validate(completion: @escaping ([ReceiptItem], Error?) -> ()) {
    let task = URLSession.shared.dataTask(with: _request) { data, response, error in
      if let dat = data,
        let receipt = try? JSONDecoder.init().decode(Receipt.self, from: dat) {
        let receipts = receipt.latest_receipt_info
        completion(receipts, nil)
      } else {
        completion([], error)
      }
    }
    task.resume()

  }

  public func syncValidate() throws -> [ReceiptItem] {
    var receipts: [ReceiptItem] = []
    var myError: Error? = nil
    lock.wait()
    validate() { r, err in
      receipts = r
      myError = err
      self.lock.signal()
    }
    lock.wait()
    defer {
      lock.signal()
    }
    if let e = myError {
      throw e
    } else {
      return receipts
    }
  }
}
