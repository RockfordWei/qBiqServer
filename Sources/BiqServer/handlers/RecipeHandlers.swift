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
	public let unit: String
	public let low: Double
	public let high: Double
	public var enabled: Bool
	public var index: Int

	public init(measurement m: String, unit u: String, low lo: Double, high hi: Double, enabled en: Bool, index i: Int) {
		low = min(lo, hi)
		high = max(lo, hi)
		measurement = m; enabled = en; index = i; unit = u
	}
}

public struct BiqRecipe: Codable {
	public let id: Foundation.UUID
	public let name: String
	public let logo: Data
	public let description: String
	public var message: String
	public var tone: Data
	public var animation: Data
	public var ranges: Data

	public init(id i: Foundation.UUID, name n: String, logo l: Data, description d: String, message m: String, tone t: Data, animation a: Data, ranges r: [BiqRange]) {
		id = i; name = n; logo = l; description = d; message = m; tone = t; animation = a;
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

struct RecipeHandlers {
	static func identity(session rs: RequestSession) throws -> RequestSession {
		return rs
	}

	static func recipeGet(session rs: RequestSession) throws -> BiqRecipe? {
		guard let id = rs.request.param(name: "id"),
			let uuid = UUID.init(uuidString: id) else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid recipe id.")
		}
		let db = try biqDatabaseInfo.deviceDb()
		let tb = db.table(BiqRecipe.self)
		return try tb.where(\BiqRecipe.id == uuid).first()
	}

	static func recipeSet(session rs: RequestSession) throws {
		guard let postBody = rs.request.postBodyBytes else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid post.")
		}
		let recipe = try JSONDecoder().decode(BiqRecipe.self, from: Data(postBody))
		let db = try biqDatabaseInfo.deviceDb()
		let tb = db.table(BiqRecipe.self)
		// !FIXIT! when upsert (INSERT ON CONFLICT) available
		if try tb.where(\BiqRecipe.id == recipe.id).count() > 0 {
			try tb.update(recipe);
		} else {
			try tb.insert(recipe)
		}
	}

	static func recipeTagAdd(session rs: RequestSession) throws {
		guard let postBody = rs.request.postBodyBytes else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid post.")
		}
		let tags = try JSONDecoder().decode([BiqRecipeTag].self, from: Data(postBody))
		let db = try biqDatabaseInfo.deviceDb()
		let tb = db.table(BiqRecipeTag.self)
		_ = tags.forEach { _ = try? tb.insert($0) }
	}

	static func recipeTagRemove(session rs: RequestSession) throws {
		guard let postBody = rs.request.postBodyBytes else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid post.")
		}
		let tags = try JSONDecoder().decode([BiqRecipeTag].self, from: Data(postBody))
		let db = try biqDatabaseInfo.deviceDb()
		let tb = db.table(BiqRecipeTag.self)
		_ = tags.forEach { _ = try? tb.where(\BiqRecipeTag.recipe == $0.recipe && \BiqRecipeTag.tag == $0.tag).delete() }
	}

	static func parseLimit(session rs: RequestSession) -> Int {
		let limit: Int
		if let limitation = rs.request.param(name: "limit"), let aLimit = Int(limitation) {
			limit = aLimit >= 0 && aLimit < 101 ? aLimit : 100
		} else {
			limit = 100
		}
		return limit
	}

	static func recipeTagGet(session rs: RequestSession) throws -> [String] {
		guard let id = rs.request.param(name: "id"), let uuid = UUID.init(uuidString: id) else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid recipe id.")
		}
		let limit = parseLimit(session: rs)
		let db = try biqDatabaseInfo.deviceDb()
		let tb = try db.table(BiqRecipeTag.self).limit(limit, skip: 0).where(\BiqRecipeTag.recipe == uuid).select()
		return tb.map { $0.tag }
	}
	
	static func search(session rs: RequestSession) throws -> [BiqRecipe] {
		guard let keywords = rs.request.param(name: "keywords") else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid keywords")
		}
		let blank = CharacterSet.init(charactersIn: " \t\r\n")
		let keys = keywords.split(separator: " ").compactMap { String($0).trimmingCharacters(in: blank ) }
		guard !keys.isEmpty else {
			throw HTTPResponseError(status: .badRequest, description: "Invalid keywords")
		}
		let limit = parseLimit(session: rs)
		let nameLike = keys.map { "name like '%\($0)%'"}.joined(separator: " OR ")
		let descLike = keys.map { "description like '%\($0)%'"}.joined(separator: " OR ")
		let tagsLike = keys.map { "tag like '%\($0)%'"}.joined(separator: " OR ")
		let sql = """
		SELECT * FROM BiqRecipe
		WHERE \(nameLike) OR \(descLike)
		OR id IN (SELECT DISTINCT recipe FROM BiqRecipeTag WHERE \(tagsLike))
		LIMIT \(limit)
		"""

		print(sql)
		let db = try biqDatabaseInfo.deviceDb()

		return try db.sql(sql, BiqRecipe.self)
	}
}
