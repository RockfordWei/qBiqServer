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

  static func jsonPath(uid: String) -> String {
    return "profiles/\(uid).json"
  }

  static func identity(session rs: RequestSession) throws -> RequestSession {
    return rs
  }

  static func upload(session rs: RequestSession) throws -> ProfileAPIResponse {
    let uid = rs.session.id.uuidString.lowercased()
    guard let bytes = rs.request.postBodyBytes else {
      return ProfileAPIResponse.init(content: "empty")
    }
    let data = Data.init(bytes: bytes)
    let prof = try JSONDecoder.init().decode(ProfileAPIResponse.self, from: data)
    let text = prof.content
    guard text.count < 1048576 else {
      return ProfileAPIResponse.init(content: "oversized")
    }
    let file = File.init(ProfileHandlers.jsonPath(uid: uid))
    try file.open(.write)
    let count = try file.write(string: text)
    file.close()
    return ProfileAPIResponse.init(content: "\(count)")
  }

  static func download(session rs: RequestSession) throws -> ProfileAPIResponse {
    guard let uid = rs.request.param(name: "uid") else {
      return ProfileAPIResponse.init()
    }
    let file = File.init(ProfileHandlers.jsonPath(uid: uid))
    try file.open(.read)
    let text = try file.readString()
    file.close()
    return ProfileAPIResponse.init(content: text)
  }
}
