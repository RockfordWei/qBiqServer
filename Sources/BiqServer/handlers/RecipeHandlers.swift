//
//  RecipeHandlers.swift
//  BiqServer
//
//  Created by Rocky Wei on 2019-05-07.
//

import Foundation
import PerfectHTTP
import PerfectCRUD
import SwiftCodables
import SAuthCodables
import PerfectLib
import PerfectPostgreSQL
import Foundation
import PerfectPostgreSQL
import PerfectCRUD

public struct Recipe: Codable, CustomStringConvertible {
	public let title: String
	public let company: String
	public let createdAt: String
	public let lastUpdate: String
	public let subtitle: String
	public let website: String
	public let companyWebsite: String
	public let companyLogo: String
	public let logo: String
	public let description: String
	public var stars: Int
	public let tags: [String]?
	public let comments: String?
	public let payload: String?
	public init(title t: String, company c: String,
							createdAt cra: String, lastUpdate last: String, subtitle sub: String,
							website web: String, companyWebsite cweb: String,
							companyLogo clogo: String, logo mylogo: String,
							description des: String, stars sta: Int,
							tags tg:[String]? = nil, comments cmt: String? = nil,
							payload paid: String? = nil) {
		title = t; company = c; createdAt = cra; lastUpdate = last;
		subtitle = sub; website = web; companyWebsite = cweb;
		companyLogo = clogo; logo = mylogo; description = des;
		stars = sta; tags = tg; comments = cmt; payload = paid
	}
}


struct RecipeHandlers {
	static func identity(session rs: RequestSession) throws -> RequestSession {
		return rs
	}

	static func recipeSearch(session rs: RequestSession) throws -> [Recipe] {
		var page = 0
		var size = 10
		if let pgStr = rs.request.param(name: "page"), let pg = Int(pgStr), pg >= 0 {
			page = pg
		}
		if let szStr = rs.request.param(name: "size"), let sz = Int(szStr), sz > 0 && sz <= 100 {
			size = sz
		}
		var whereClause = ""
		let blanks = CharacterSet(charactersIn: " \t\r\n")
		let keywordstr = rs.request.params(named: "keywords")
		let keywords = Set<String>(keywordstr
				.map { String($0.trimmingCharacters(in: blanks)).lowercased() }
				.filter { $0.count > 2 })
		if !keywordstr.isEmpty {
			let likes = keywords.map {
				"company LIKE '%\($0)%' OR title LIKE '%\($0)%' OR subtitle LIKE '%\($0)%' OR description LIKE '%\($0)%'"
				}.joined(separator: " OR ")
			let tags = keywords.map { "tags ?| array['\($0)']" }.joined(separator: " OR ")
			whereClause = "WHERE \(likes) OR \(tags)"
		}
		let sql = "SELECT * FROM Recipe \(whereClause) ORDER BY title, company ASC OFFSET \(page) LIMIT \(size)"
		CRUDLogging.log(.query, sql)
		let db = try biqDatabaseInfo.deviceDb()
		let records = try db.sql(sql, Recipe.self)
		return records
	}
}
