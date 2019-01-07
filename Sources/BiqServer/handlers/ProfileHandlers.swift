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

public struct ProfileAPIResponse: Codable {
  public var content = ""
}

public struct ProfileHandlers {

  static let path = "profiles"
  static func identity(session rs: RequestSession) throws -> RequestSession {
    return rs
  }

  static func upload(session rs: RequestSession) throws -> ProfileAPIResponse {
    let uid = rs.session.id.uuidString.lowercased()
    guard let bytes = rs.request.postBodyBytes else {
      return ProfileAPIResponse.init(content: "empty")
    }
    guard bytes.count < 1048576 else {
      return ProfileAPIResponse.init(content: "oversized")
    }
    let path = "\(ProfileHandlers.path)/\(uid)"
    let file = File.init(path)
    try file.open(.write)
    let count = try file.write(bytes: bytes)
    file.close()
    return ProfileAPIResponse.init(content: "\(count)")
  }

  static func download(session rs: RequestSession) throws -> ProfileAPIResponse {
    guard let uid = rs.request.param(name: "uid") else {
      return ProfileAPIResponse.init()
    }
    let path = "\(ProfileHandlers.path)/\(uid)"
    let file = File.init(path)
    try file.open(.read)
    let bytes = try file.readSomeBytes(count: file.size)
    file.close()
    guard let encoded = bytes.encode(.base64),
      let str = String.init(validatingUTF8: encoded) else {
        return ProfileAPIResponse.init()
    }
    return ProfileAPIResponse.init(content: str)
  }
}
