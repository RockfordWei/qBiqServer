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

}
