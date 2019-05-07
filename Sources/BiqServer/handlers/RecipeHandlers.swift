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

public struct BiqRange: Codable {
	public let measurement: String
	public let low: Double
	public let high: Double
	public var enabled: Bool
	public var index: Int

	public init(measurement m: String, low lo: Double, high hi: Double, enabled en: Bool, index i: Int) {
		measurement = m; low = lo; high = hi; enabled = en; index = i
	}
}

public struct BiqRecipe: Codable {
	public let id: Foundation.UUID
	public let name: String
	public let logo: Data
	public let description: String
	public var searching: Int
	public var using: Int
	public var ranges: Data
	public var message: String
	public var tone: Data
	public var animation: Data

	public init(id i: Foundation.UUID, name n: String, logo l: Data, description d: String, searching s: Int, using u: Int, message m: String, ranges r: [BiqRange], tone t: Data, animation a: Data) {
		id = i; name = n; logo = l; description = d; searching = s; using = u; message = m; tone = t; animation = a;
		do {
			ranges = try JSONEncoder().encode(r)
		} catch {
			ranges = Data()
		}
	}
}

public struct BiqRecipeTag: Codable {
	public let recipe: Foundation.UUID
	public let tag: String
	public init(recipe r: Foundation.UUID, tag t: String) {
		recipe = r; tag = t
	}
}

public struct BiqRecipeSearch: Codable {
	public let limit: Int
	public let tags: [String]
	public init(limit l: Int, tags t: [String]) {
		limit = BiqRecipeSearch.validate(l); tags = t
	}
	public static func validate(_ aLimit: Int) -> Int {
		return aLimit > 9 && aLimit < 1001 ? aLimit: 10
	}
}

struct RecipeHandlers {
	static func identity(session rs: RequestSession) throws -> RequestSession {
		return rs
	}

	static func recipeGet(session rs: RequestSession) throws -> [BiqRecipe] {
		guard let postBody = rs.request.postBodyBytes else {
			throw HTTPResponseError(status: .badRequest, description: "Null post body.")
		}
		let search = try JSONDecoder().decode(BiqRecipeSearch.self, from: Data(postBody))
		let whereClause = search.tags.map { "id::text = '\($0)'" }.joined(separator: " OR ")
		guard !whereClause.isEmpty else { return [] }

		let db = try biqDatabaseInfo.deviceDb()
		let limit = BiqRecipeSearch.validate(search.limit)
		return try db.sql("SELECT * FROM BiqRecipe WHERE \(whereClause) LIMIT \(limit)", BiqRecipe.self)
	}

	static func recipeSet(session rs: RequestSession) throws {
		guard let postBody = rs.request.postBodyBytes else {
			throw HTTPResponseError(status: .badRequest, description: "Null post body.")
		}
		let recipe = try JSONDecoder().decode(BiqRecipe.self, from: Data(postBody))
		let db = try biqDatabaseInfo.deviceDb()
		let tb = db.table(BiqRecipe.self)
		if try tb.where(\BiqRecipe.id == recipe.id).count() > 0 {
			try db.transaction {
				try tb.where(\BiqRecipe.id == recipe.id).delete()
				try tb.insert(recipe)
			}
		} else {
			try tb.insert(recipe)
		}
	}

	static func recipeTagAdd(session rs: RequestSession) throws {
		guard let postBody = rs.request.postBodyBytes else {
			throw HTTPResponseError(status: .badRequest, description: "Null post body.")
		}
		let tag = try JSONDecoder().decode(BiqRecipeTag.self, from: Data(postBody))
		let db = try biqDatabaseInfo.deviceDb()
		let tb = db.table(BiqRecipeTag.self)
		try tb.insert(tag)
	}

	static func recipeTagRemove(session rs: RequestSession) throws {
		guard let postBody = rs.request.postBodyBytes else {
			throw HTTPResponseError(status: .badRequest, description: "Null post body.")
		}
		let tag = try JSONDecoder().decode(BiqRecipeTag.self, from: Data(postBody))
		let db = try biqDatabaseInfo.deviceDb()
		try db.table(BiqRecipeTag.self).where(\BiqRecipeTag.recipe == tag.recipe && \BiqRecipeTag.tag == tag.tag).delete()
	}

	static func recipeTagGet(session rs: RequestSession) throws -> [String] {
		guard let id = rs.request.param(name: "id") else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid recipe id.")
		}
		guard let uuid = UUID.init(uuidString: id) else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid recipe uuid.")
		}
		let limit: Int
		if let limitation = rs.request.param(name: "limit"), let aLimit = Int(limitation) {
			limit = BiqRecipeSearch.validate(aLimit)
		} else {
			limit = 100
		}
		let db = try biqDatabaseInfo.deviceDb()
		let tb = try db.table(BiqRecipeTag.self).limit(limit, skip: 0).where(\BiqRecipeTag.recipe == uuid).select()
		return tb.map { $0.tag }
	}
	
	static func search(session rs: RequestSession) throws -> [String] {
		let search: BiqRecipeSearch
		if let postBody = rs.request.postBodyBytes {
			search = try JSONDecoder().decode(BiqRecipeSearch.self, from: Data(postBody))
		} else {
			search = BiqRecipeSearch(limit: 10, tags: [])
		}
		let limit = search.limit > 9 && search.limit < 1001 ? search.limit : 10
		let db = try biqDatabaseInfo.deviceDb()
		let likes = search.tags.map { "tag like '%\($0)%'" }.joined(separator: " OR ")
		let whereClause = likes.isEmpty ? "" : "WHERE \(likes)"
		let sql = "SELECT DISTINCT recipe::text FROM BiqRecipeTag \(whereClause) LIMIT \(limit)"
		return try db.sql(sql, String.self)
	}
}
